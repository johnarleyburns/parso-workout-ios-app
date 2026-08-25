import Foundation

public struct OptimizedCoachPlan: Sendable, Equatable {
    public let plannedStrengthSessions: [CoachSession]
    public let unresolvedDeficits: [MuscleGroup: Double]
    public let diagnostics: [PlanningDiagnostic]

    public init(plannedStrengthSessions: [CoachSession],
                unresolvedDeficits: [MuscleGroup: Double] = [:],
                diagnostics: [PlanningDiagnostic] = []) {
        self.plannedStrengthSessions = plannedStrengthSessions
        self.unresolvedDeficits = unresolvedDeficits
        self.diagnostics = diagnostics
    }

    public static let empty = OptimizedCoachPlan(plannedStrengthSessions: [])
}

public struct PlanningDiagnostic: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable {
        case plannedExistingSlot
        case plannedExtraSlot
        case reshapedCandidate
        case synthesizedSession
        case skippedRestDay
        case recoveryBlocked
        case noStrengthSlots
        case unresolvedDeficit
    }

    public let id: String
    public let kind: Kind
    public let message: String
    public let group: MuscleGroup?
    public let value: Double?

    public init(id: String, kind: Kind, message: String,
                group: MuscleGroup? = nil, value: Double? = nil) {
        self.id = id
        self.kind = kind
        self.message = message
        self.group = group
        self.value = value
    }
}

/// Tunable guardrails the plan optimizer respects. `.safe` is the coach's default
/// (never plans back-to-back hard days, caps session size, stays under MRV, honors
/// rest days). `.meetDeficits` is the user-invoked "ignore constraints and plan to
/// meet my weekly deficits" override: it relaxes those guardrails so the week's
/// volume targets can actually be closed even at the cost of consecutive strength
/// days, oversized sessions, and exceeding MRV.
public struct PlanningConstraintPolicy: Sendable, Equatable {
    public var maxSetsPerExercise: Int
    public var maxExercisesPerSession: Int
    public var maxTotalSetsPerSession: Int
    public var maxExtraStrengthSlots: Int
    /// When true, hard strength work is blocked while the whole-body recovery
    /// window is still open.
    public var respectsRecoveryEligibility: Bool
    /// When true, strength work is never planned on the user's rest days.
    public var respectsRestDays: Bool
    /// When true, per-exercise set counts are capped so projected volume stays at
    /// or below MRV.
    public var respectsMRVCeiling: Bool
    /// When true, extra (added) strength slots are only created if the user allows
    /// two-a-days; when false the override may add slots regardless.
    public var requiresTwoADayPreferenceForExtraSlots: Bool

    public init(maxSetsPerExercise: Int,
                maxExercisesPerSession: Int,
                maxTotalSetsPerSession: Int,
                maxExtraStrengthSlots: Int,
                respectsRecoveryEligibility: Bool,
                respectsRestDays: Bool,
                respectsMRVCeiling: Bool,
                requiresTwoADayPreferenceForExtraSlots: Bool) {
        self.maxSetsPerExercise = maxSetsPerExercise
        self.maxExercisesPerSession = maxExercisesPerSession
        self.maxTotalSetsPerSession = maxTotalSetsPerSession
        self.maxExtraStrengthSlots = maxExtraStrengthSlots
        self.respectsRecoveryEligibility = respectsRecoveryEligibility
        self.respectsRestDays = respectsRestDays
        self.respectsMRVCeiling = respectsMRVCeiling
        self.requiresTwoADayPreferenceForExtraSlots = requiresTwoADayPreferenceForExtraSlots
    }

    /// The coach's default guardrails. ~6 exercises / ~18 sets per session
    /// (4 compound + 2 isolation) fits whole-body weekly coverage for 2-3
    /// strength days; ~50-55 min.
    public static let safe = PlanningConstraintPolicy(
        maxSetsPerExercise: 4,
        maxExercisesPerSession: 6,
        maxTotalSetsPerSession: 18,
        maxExtraStrengthSlots: 1,
        respectsRecoveryEligibility: true,
        respectsRestDays: true,
        respectsMRVCeiling: true,
        requiresTwoADayPreferenceForExtraSlots: true)

    /// User opt-out: relax the guardrails to close the week's volume deficits.
    public static let meetDeficits = PlanningConstraintPolicy(
        maxSetsPerExercise: 8,
        maxExercisesPerSession: 12,
        maxTotalSetsPerSession: 60,
        maxExtraStrengthSlots: 7,
        respectsRecoveryEligibility: false,
        respectsRestDays: false,
        respectsMRVCeiling: false,
        requiresTwoADayPreferenceForExtraSlots: false)
}

public enum CoachPlanOptimizer {

    private struct PlanningSlot: Equatable {
        let id: String
        let date: Date
        let isExtra: Bool
    }

    private struct CandidatePlan {
        let session: CoachSession
        let remainingDeficits: [MuscleGroup: Double]
        let score: CandidateScore
    }

    private struct CandidateScore: Comparable {
        let remainingGroups: Int
        let remainingMagnitude: Double
        let totalSets: Int
        let overMRV: Double
        let unfamiliarExercises: Int
        let sessionID: String

        static func < (lhs: CandidateScore, rhs: CandidateScore) -> Bool {
            if lhs.remainingGroups != rhs.remainingGroups { return lhs.remainingGroups < rhs.remainingGroups }
            if lhs.remainingMagnitude != rhs.remainingMagnitude { return lhs.remainingMagnitude < rhs.remainingMagnitude }
            if lhs.totalSets != rhs.totalSets { return lhs.totalSets < rhs.totalSets }
            if lhs.overMRV != rhs.overMRV { return lhs.overMRV < rhs.overMRV }
            if lhs.unfamiliarExercises != rhs.unfamiliarExercises { return lhs.unfamiliarExercises < rhs.unfamiliarExercises }
            return lhs.sessionID < rhs.sessionID
        }
    }

    public static func optimize(trainingFacts: TrainingFacts,
                                coachFacts: CoachFacts,
                                weeklyPlan: WeeklyPlan,
                                schedulePreferences: CoachSchedulePreferences,
                                candidates candidateSessions: [CoachSession],
                                constraintPolicy: PlanningConstraintPolicy = .safe) -> OptimizedCoachPlan {
        let lowGroups = weeklyCoverageGroups(in: trainingFacts,
                                             tracked: schedulePreferences.trackedMuscleGroups)
        let strengthCandidates = uniqueStrengthCandidates(candidateSessions)
        let desiredSetsPerExercise = schedulePreferences.desiredSetsPerExercise
        var diagnostics: [PlanningDiagnostic] = []

        var slots = remainingStrengthSlots(in: weeklyPlan,
                                           facts: coachFacts,
                                           schedulePreferences: schedulePreferences,
                                           policy: constraintPolicy,
                                           diagnostics: &diagnostics)

        if slots.isEmpty {
            diagnostics.append(PlanningDiagnostic(
                id: "noStrengthSlots",
                kind: .noStrengthSlots,
                message: "No eligible remaining strength slots were available in this week's plan."))
        }

        // When no remaining slots exist at all but today is a valid training day,
        // add an ad-hoc slot so residual volume can be routed into a self-scheduled
        // session (Phase 3: volume routing fix). Guardrails: only self-schedule to
        // close a genuine weekly strength shortfall (at least one group below MEV),
        // and never manufacture a two-a-day the user disallowed — if today already
        // holds a non-rest session and two-a-days are off, defer to the aggregate
        // nag rather than stacking a second session on the day.
        let todayStart = Calendar.current.startOfDay(for: coachFacts.referenceDate)
        let hasTodaySlot = slots.contains { Calendar.current.isDate($0.date, inSameDayAs: todayStart) }
        let todayHasOtherSession = weeklyPlan.days.contains { day in
            Calendar.current.isDate(day.date, inSameDayAs: todayStart)
                && day.sessions.contains { !$0.isRest }
        }
        let adhocWouldForceTwoADay = constraintPolicy.requiresTwoADayPreferenceForExtraSlots
            && !schedulePreferences.allowsTwoADays
            && todayHasOtherSession
        if !hasTodaySlot, slots.isEmpty, !lowGroups.isEmpty, !adhocWouldForceTwoADay,
           hardStrengthAllowed(on: todayStart, facts: coachFacts,
                               schedulePreferences: schedulePreferences,
                               policy: constraintPolicy) {
            slots.append(PlanningSlot(id: "today.adhoc", date: todayStart, isExtra: false))
        }

        var projected = trainingFacts.weeklySetsByGroup
        var planned: [CoachSession] = []
        // Plan toward the *productive* midpoint (issue 1), not the bare MEV floor,
        // so small muscles (abs, calves, arms) get a genuinely productive dose.
        var deficits = lowDeficits(for: lowGroups, projected: projected,
                                   experience: trainingFacts.experience, target: .productive)

        plan(slots: slots,
             into: &planned,
             projected: &projected,
             deficits: &deficits,
             lowGroups: lowGroups,
             trainingFacts: trainingFacts,
             coachFacts: coachFacts,
             strengthCandidates: strengthCandidates,
             desiredSetsPerExercise: desiredSetsPerExercise,
             policy: constraintPolicy,
             diagnostics: &diagnostics)

        let mayAddExtraSlots = !constraintPolicy.requiresTwoADayPreferenceForExtraSlots
            || schedulePreferences.allowsTwoADays
        if !deficits.isEmpty, mayAddExtraSlots {
            let extras = extraStrengthSlots(in: weeklyPlan,
                                           existingSlots: slots,
                                           facts: coachFacts,
                                           schedulePreferences: schedulePreferences,
                                           policy: constraintPolicy,
                                           diagnostics: &diagnostics)
            slots.append(contentsOf: extras)
            plan(slots: extras,
                 into: &planned,
                 projected: &projected,
                 deficits: &deficits,
                 lowGroups: lowGroups,
                 trainingFacts: trainingFacts,
                 coachFacts: coachFacts,
                 strengthCandidates: strengthCandidates,
                 desiredSetsPerExercise: desiredSetsPerExercise,
                 policy: constraintPolicy,
                 diagnostics: &diagnostics)
        }

        // Planning chases the productive midpoint (issue 1), but a *genuine*
        // shortfall — the thing the coach nags about — is only a group still below
        // its minimum effective volume (MEV) after all safe planned work. Reporting
        // against MEV (not the aspirational productive target) reconciles the old
        // "under-dose AND nag" contradiction: a group trained to a productive dose is
        // above MEV, so it never surfaces as an unresolved deficit or a user nag.
        let reportedDeficits = lowDeficits(for: lowGroups, projected: projected,
                                           experience: trainingFacts.experience, target: .mev)

        for (group, value) in reportedDeficits.sorted(by: groupDeficitSort) {
            diagnostics.append(PlanningDiagnostic(
                id: "unresolved.\(group.rawValue)",
                kind: .unresolvedDeficit,
                message: "\(group.displayName) remains \(Format.sets(value)) sets below the starting range after safe planned work.",
                group: group,
                value: value))
        }

        return OptimizedCoachPlan(
            plannedStrengthSessions: planned,
            unresolvedDeficits: reportedDeficits,
            diagnostics: diagnostics)
    }

    // MARK: - Session-structure classification (evidence: ramosCampoSplit2024)

    /// How a built strength session is organised. Surfaced to the user so the
    /// optimizer's full-body-vs-split reasoning is transparent ("open door").
    public enum SessionStructure: String, Sendable, Equatable {
        case fullBody
        case upperFocus
        case lowerFocus
        case focused
    }

    /// Classify a strength session by the muscle groups its exercises cover.
    /// Non-strength or exercise-less sessions return `nil` (no structure to explain).
    public static func classifyStructure(of session: CoachSession) -> SessionStructure? {
        guard session.kind == .strength, let exercises = session.exercises, !exercises.isEmpty else {
            return nil
        }
        let groups = coveredGroups(of: session)
        guard !groups.isEmpty else { return nil }
        // 20 groups resolve finer than the retired 8 body parts, so the full-body
        // threshold scales with them: 8 of 20 is the same share of the body that
        // 5 of 8 parts was, and keeps a genuine upper/lower split from reading as
        // full-body just because it touches more named groups.
        if groups.count >= 8 { return .fullBody }
        let lower = groups.intersection(MuscleGroup.lowerBody)
        let upper = groups.subtracting(MuscleGroup.lowerBody).subtracting([.abdominals])
        if upper.isEmpty && !lower.isEmpty { return .lowerFocus }
        if lower.isEmpty && upper.count >= 2 { return .upperFocus }
        return .focused
    }

    /// Build the user-facing, cited `ObservedFact` explaining a session's structure.
    public static func sessionStructureFact(for session: CoachSession, now: Date) -> ObservedFact? {
        guard let structure = classifyStructure(of: session) else { return nil }
        let groups = coveredGroups(of: session)
        let value: String
        let detail: String
        switch structure {
        case .fullBody:
            value = "Full-body"
            detail = "Coach built a full-body session to spread weekly volume efficiently across fewer training days."
        case .upperFocus:
            value = "Upper body"
            detail = "Coach focused this session on your upper body to allow adequate per-muscle volume within a single workout."
        case .lowerFocus:
            value = "Lower body"
            detail = "Coach focused this session on your lower body to allow adequate per-muscle volume within a single workout."
        case .focused:
            let names = MuscleGroup.sorted(groups)
                .prefix(2)
                .map { $0.displayName.lowercased() }
                .joined(separator: " & ")
            value = "Focused"
            detail = "Coach targeted \(names) specifically to close a weekly volume deficit."
        }
        return ObservedFact(
            kind: .sessionStructure,
            title: "Session structure",
            value: value,
            detail: detail,
            occurredAt: now,
            citationIds: CitationRegistry.citationPool(for: .sessionStructure).citationIds)
    }

    private static func coveredGroups(of session: CoachSession) -> Set<MuscleGroup> {
        (session.exercises ?? []).reduce(into: Set<MuscleGroup>()) { acc, exercise in
            acc.formUnion(groupsCovered(by: exercise))
        }
    }

    private static func plan(slots: [PlanningSlot],
                              into planned: inout [CoachSession],
                              projected: inout [MuscleGroup: Double],
                              deficits: inout [MuscleGroup: Double],
                              lowGroups: Set<MuscleGroup>,
                              trainingFacts: TrainingFacts,
                              coachFacts: CoachFacts,
                              strengthCandidates: [CoachSession],
                              desiredSetsPerExercise: Int,
                              policy: PlanningConstraintPolicy,
                              diagnostics: inout [PlanningDiagnostic]) {
        for (i, slot) in slots.enumerated() {
            let slotsLeft = slots.count - i
            let slotDeficits: [MuscleGroup: Double] = deficits.mapValues { ceil($0 / Double(slotsLeft)) }
            // Exercises already assigned to earlier days in this generation pass, so
            // per-day selection can rotate a movement pattern's exercise *identity*
            // across days (issue: "rotary torso" every day) instead of repeating one
            // historical favorite.
            let usedThisWeek = Set(planned.flatMap { ($0.exercises ?? []).map(\.name) })
            let choice = chooseSession(
                for: slot,
                deficits: slotsLeft > 1 ? slotDeficits : deficits,
                projected: projected,
                trainingFacts: trainingFacts,
                coachFacts: coachFacts,
                strengthCandidates: strengthCandidates,
                usedThisWeek: usedThisWeek,
                desiredSetsPerExercise: desiredSetsPerExercise,
                policy: policy)
            planned.append(choice.session)
            let added = PlanAwareWeeklyAccounting.plannedSetsByGroup(from: [choice.session])
            projected = projected.merging(added) { $0 + $1 }
            deficits = lowDeficits(for: lowGroups, projected: projected, experience: trainingFacts.experience)

            let kind: PlanningDiagnostic.Kind = slot.isExtra ? .plannedExtraSlot : .plannedExistingSlot
            diagnostics.append(PlanningDiagnostic(
                id: "\(kind.rawValue).\(slot.id)",
                kind: kind,
                message: "Planned \(choice.session.title) for \(slot.id)."))

            if choice.session.id.contains(".synthetic.") {
                diagnostics.append(PlanningDiagnostic(
                    id: "synthesized.\(slot.id)",
                    kind: .synthesizedSession,
                    message: "Synthesized a focused strength session for remaining volume deficits."))
            } else if choice.session.id.contains(".optimized.") {
                diagnostics.append(PlanningDiagnostic(
                    id: "reshaped.\(slot.id)",
                    kind: .reshapedCandidate,
                    message: "Reshaped an existing strength candidate to better cover projected deficits."))
            }
        }
    }

    private static func chooseSession(for slot: PlanningSlot,
                                      deficits: [MuscleGroup: Double],
                                      projected: [MuscleGroup: Double],
                                      trainingFacts: TrainingFacts,
                                      coachFacts: CoachFacts,
                                      strengthCandidates: [CoachSession],
                                      usedThisWeek: Set<String>,
                                      desiredSetsPerExercise: Int,
                                      policy: PlanningConstraintPolicy) -> CandidatePlan {
        let candidatePool = strengthCandidates.isEmpty ? [syntheticBaseSession()] : strengthCandidates
        let options = candidatePool.map {
            optimizedVersion(of: $0,
                             slot: slot,
                             deficits: deficits,
                             projected: projected,
                             trainingFacts: trainingFacts,
                             coachFacts: coachFacts,
                             usedThisWeek: usedThisWeek,
                             desiredSetsPerExercise: desiredSetsPerExercise,
                             policy: policy)
        } + [
            optimizedVersion(of: syntheticBaseSession(),
                             slot: slot,
                             deficits: deficits,
                             projected: projected,
                             trainingFacts: trainingFacts,
                             coachFacts: coachFacts,
                             usedThisWeek: usedThisWeek,
                             desiredSetsPerExercise: desiredSetsPerExercise,
                             policy: policy)
        ]

        return options.min { $0.score < $1.score } ?? CandidatePlan(
            session: materialize(syntheticBaseSession(), slot: slot,
                                 exercises: defaultExercises(for: deficits,
                                                             facts: trainingFacts,
                                                             coachFacts: coachFacts,
                                                             slot: slot,
                                                             desiredSetsPerExercise: desiredSetsPerExercise,
                                                             policy: policy),
                                 targetedGroups: Set(deficits.keys), synthesized: true),
            remainingDeficits: deficits,
            score: CandidateScore(remainingGroups: deficits.count,
                                  remainingMagnitude: deficits.values.reduce(0, +),
                                  totalSets: 0,
                                  overMRV: 0,
                                  unfamiliarExercises: 0,
                                  sessionID: "strength.synthetic"))
    }

    private static func optimizedVersion(of base: CoachSession,
                                         slot: PlanningSlot,
                                         deficits: [MuscleGroup: Double],
                                         projected: [MuscleGroup: Double],
                                         trainingFacts: TrainingFacts,
                                         coachFacts: CoachFacts,
                                         usedThisWeek: Set<String>,
                                         desiredSetsPerExercise: Int,
                                         policy: PlanningConstraintPolicy) -> CandidatePlan {
        let originalNames = Set((base.exercises ?? []).map(\.name))
        let exercises = reshapedExercises(from: base.exercises ?? [],
                                          deficits: deficits,
                                          projected: projected,
                                          trainingFacts: trainingFacts,
                                          coachFacts: coachFacts,
                                          slot: slot,
                                          usedThisWeek: usedThisWeek,
                                          desiredSetsPerExercise: desiredSetsPerExercise,
                                          policy: policy)
        let added = PlanAwareWeeklyAccounting.plannedSetsByGroup(from: exercises)
        let nextProjected = projected.merging(added) { $0 + $1 }
        let remaining = lowDeficits(for: Set(deficits.keys),
                                    projected: nextProjected,
                                    experience: trainingFacts.experience)
        let totalSets = exercises.reduce(0) { $0 + max(1, $1.sets ?? 3) }
        let unfamiliar = exercises.filter { !originalNames.contains($0.name) }.count
        let session = materialize(base,
                                  slot: slot,
                                  exercises: exercises,
                                  targetedGroups: Set(deficits.keys),
                                  synthesized: base.id == syntheticBaseSession().id)
        let score = CandidateScore(
            remainingGroups: remaining.count,
            remainingMagnitude: remaining.values.reduce(0, +),
            totalSets: totalSets,
            overMRV: overMRVAmount(projected: nextProjected, experience: trainingFacts.experience),
            unfamiliarExercises: unfamiliar,
            sessionID: session.id)
        return CandidatePlan(session: session, remainingDeficits: remaining, score: score)
    }

    private static func reshapedExercises(from baseExercises: [CoachSession.RecommendedExercise],
                                          deficits: [MuscleGroup: Double],
                                          projected: [MuscleGroup: Double],
                                          trainingFacts: TrainingFacts,
                                          coachFacts: CoachFacts,
                                          slot: PlanningSlot,
                                          usedThisWeek: Set<String>,
                                          desiredSetsPerExercise: Int,
                                          policy: PlanningConstraintPolicy) -> [CoachSession.RecommendedExercise] {
        guard !deficits.isEmpty else {
            let preserved = baseExercises
                .filter { isExerciseEligible($0, on: slot.date, facts: coachFacts, policy: policy) }
                .prefix(policy.maxExercisesPerSession)
                .map { exercise in
                    copy(exercise,
                         sets: min(policy.maxSetsPerExercise, max(1, exercise.sets ?? desiredSetsPerExercise)),
                         goal: trainingFacts.goal,
                         coachFacts: coachFacts,
                         trainingFacts: trainingFacts)
                }
            if !preserved.isEmpty {
                return rotatedForVariety(Array(preserved), usedThisWeek: usedThisWeek,
                                         trainingFacts: trainingFacts, coachFacts: coachFacts,
                                         slot: slot, policy: policy)
            }
            return ["Back Squat", "Bench Press", "Barbell Row", "Romanian Deadlift"]
                .map {
                    copy(CoachSession.RecommendedExercise(name: $0),
                         sets: min(policy.maxSetsPerExercise, max(1, desiredSetsPerExercise)),
                         goal: trainingFacts.goal,
                         coachFacts: coachFacts,
                         trainingFacts: trainingFacts)
                }
        }

        var selected: [CoachSession.RecommendedExercise] = []
        var sessionSets = 0
        var runningProjected = projected

        let usefulBase = baseExercises
            .filter { exerciseHelps($0, deficits: deficits) }
            .sorted { a, b in
                let ascore = exerciseDeficitScore(a, deficits: deficits)
                let bscore = exerciseDeficitScore(b, deficits: deficits)
                if ascore != bscore { return ascore > bscore }
                return a.name < b.name
            }

        // Pass 1 (coverage): allocate each exercise enough sets to reach the MEV
        // floor for the groups it covers. Targeting MEV first guarantees whole-body
        // breadth fits inside the session budget — a productive top-up (pass 3)
        // then raises the dose toward the midpoint with whatever budget is left.
        for exercise in usefulBase {
            guard selected.count < policy.maxExercisesPerSession else { break }
            guard isExerciseEligible(exercise, on: slot.date, facts: coachFacts, policy: policy) else { continue }
            let sets = plannedSets(for: exercise,
                                   deficits: lowDeficits(for: Set(deficits.keys),
                                                         projected: runningProjected,
                                                         experience: trainingFacts.experience,
                                                         target: .mev),
                                   projected: runningProjected,
                                   experience: trainingFacts.experience,
                                   desiredSetsPerExercise: desiredSetsPerExercise,
                                   policy: policy)
            guard sets > 0, sessionSets + sets <= policy.maxTotalSetsPerSession else { continue }
            let planned = copy(exercise, sets: sets, goal: trainingFacts.goal,
                               coachFacts: coachFacts, trainingFacts: trainingFacts)
            selected.append(planned)
            sessionSets += sets
            runningProjected = runningProjected.merging(
                PlanAwareWeeklyAccounting.plannedSetsByGroup(from: [planned])) { $0 + $1 }
        }

        // Pass 2 (breadth): add movements for any group still below MEV that the
        // base candidate didn't cover, so the coach hits every weekly target.
        var remaining = lowDeficits(for: Set(deficits.keys),
                                    projected: runningProjected,
                                    experience: trainingFacts.experience,
                                    target: .mev)
        while !remaining.isEmpty,
              selected.count < policy.maxExercisesPerSession,
              sessionSets < policy.maxTotalSetsPerSession {
            guard let group = remaining.sorted(by: groupDeficitSort).first?.key,
                  let next = bestExercise(for: group,
                                          existing: selected + baseExercises,
                                          facts: trainingFacts,
                                          coachFacts: coachFacts,
                                          slot: slot,
                                          desiredSetsPerExercise: desiredSetsPerExercise,
                                          policy: policy) else {
                break
            }
            if selected.contains(where: { $0.name == next.name }) {
                break
            }
            let sets = plannedSets(for: next,
                                   deficits: remaining,
                                   projected: runningProjected,
                                   experience: trainingFacts.experience,
                                   desiredSetsPerExercise: desiredSetsPerExercise,
                                   policy: policy)
            guard sets > 0, sessionSets + sets <= policy.maxTotalSetsPerSession else { break }
            let planned = copy(next, sets: sets, goal: trainingFacts.goal,
                               coachFacts: coachFacts, trainingFacts: trainingFacts)
            selected.append(planned)
            sessionSets += sets
            runningProjected = runningProjected.merging(
                PlanAwareWeeklyAccounting.plannedSetsByGroup(from: [planned])) { $0 + $1 }
            remaining = lowDeficits(for: Set(deficits.keys),
                                    projected: runningProjected,
                                    experience: trainingFacts.experience,
                                    target: .mev)
        }

        // Pass 3 (productive top-up): with every below-MEV group now covered, spend
        // any remaining session budget raising set counts toward the productive
        // midpoint (issue 1). Never exceeds per-exercise / total-set caps or MRV.
        if !selected.isEmpty {
            var madeProgress = true
            while madeProgress, sessionSets < policy.maxTotalSetsPerSession {
                madeProgress = false
                for index in selected.indices {
                    guard sessionSets < policy.maxTotalSetsPerSession else { break }
                    let exercise = selected[index]
                    let currentSets = exercise.sets ?? 0
                    guard currentSets < policy.maxSetsPerExercise else { continue }
                    // Only top up while a covered group is still short of productive.
                    let perSet = PlanAwareWeeklyAccounting.plannedSetsByGroup(from: [copy(exercise, sets: 1,
                                                                                          goal: trainingFacts.goal,
                                                                                          trainingFacts: trainingFacts)])
                    let productiveDeficits = lowDeficits(for: Set(perSet.keys),
                                                         projected: runningProjected,
                                                         experience: trainingFacts.experience,
                                                         target: .productive)
                    guard perSet.contains(where: { productiveDeficits[$0.key] != nil && $0.value > 0 }) else { continue }
                    // Respect the MRV ceiling per covered group.
                    if policy.respectsMRVCeiling {
                        let wouldExceedMRV = perSet.contains { group, contribution in
                            guard contribution > 0 else { return false }
                            let mrv = VolumeLandmarks.bands(for: group, experience: trainingFacts.experience).mrv
                            return (runningProjected[group] ?? 0) + contribution > mrv
                        }
                        if wouldExceedMRV { continue }
                    }
                    selected[index] = copy(exercise, sets: currentSets + 1, goal: trainingFacts.goal,
                                           coachFacts: coachFacts, trainingFacts: trainingFacts)
                    sessionSets += 1
                    runningProjected = runningProjected.merging(perSet) { $0 + $1 }
                    madeProgress = true
                }
            }
        }

        if selected.isEmpty {
            let fallback = defaultExercises(for: deficits,
                                            facts: trainingFacts,
                                            coachFacts: coachFacts,
                                            slot: slot,
                                            desiredSetsPerExercise: desiredSetsPerExercise,
                                            policy: policy)
                .filter { isExerciseEligible($0, on: slot.date, facts: coachFacts, policy: policy) }
                .prefix(policy.maxExercisesPerSession)
            selected = Array(fallback)
        }

        selected = rotatedForVariety(selected, usedThisWeek: usedThisWeek,
                                     trainingFacts: trainingFacts, coachFacts: coachFacts,
                                     slot: slot, policy: policy)

        return selected.sorted { a, b in
            let agroup = primarySortGroup(for: a)
            let bgroup = primarySortGroup(for: b)
            if agroup != bgroup {
                return MuscleGroup.canonicalIndex(agroup) < MuscleGroup.canonicalIndex(bgroup)
            }
            return a.name < b.name
        }
    }

    // MARK: - Cross-day exercise variety (anti-repeat rotation)

    /// Rotate exercise *identity* across the days of one planning pass: when a
    /// selected exercise was already assigned to an earlier day this week, swap it
    /// for an equivalent alternative — same covered muscle groups, recovery-eligible,
    /// not yet used — preferring the user's own trained lifts for the movement
    /// pattern (ranked by `CoachSession.trainedExerciseCandidates`), then catalog
    /// defaults. The exact group-set match keeps the coverage/MRV accounting and the
    /// prescription (sets, reps, RIR, ladder) identical, so only the identity
    /// varies. Interchangeable movements (mostly isolation, e.g. every core slot
    /// resolving to "rotary torso") rotate; compounds with unique coverage stay put.
    private static func rotatedForVariety(_ selected: [CoachSession.RecommendedExercise],
                                          usedThisWeek: Set<String>,
                                          trainingFacts: TrainingFacts,
                                          coachFacts: CoachFacts,
                                          slot: PlanningSlot,
                                          policy: PlanningConstraintPolicy) -> [CoachSession.RecommendedExercise] {
        guard !usedThisWeek.isEmpty else { return selected }
        var used = usedThisWeek
        var result: [CoachSession.RecommendedExercise] = []
        for exercise in selected {
            if used.contains(exercise.name),
               let alternative = varietyAlternative(for: exercise,
                                                    avoiding: used.union(result.map(\.name)),
                                                    trainingFacts: trainingFacts,
                                                    coachFacts: coachFacts,
                                                    slot: slot,
                                                    policy: policy) {
                result.append(alternative)
            } else {
                result.append(exercise)
            }
            used.insert(result[result.count - 1].name)
        }
        return result
    }

    /// An equivalent, not-yet-used replacement for `exercise`: covers exactly the
    /// same muscle groups (so coverage and MRV math are unchanged) and passes the
    /// recovery-eligibility gate. Candidates come from the user's ranked trained
    /// lifts — the exercise's own movement patterns first, then any other trained
    /// lift that covers the same groups (pattern keyword inference can misfile a
    /// movement, e.g. "crunch" contains "run") — then the catalog defaults for its
    /// primary group. Returns nil when no equivalent exists — the original is kept
    /// rather than degrading coverage.
    private static func varietyAlternative(for exercise: CoachSession.RecommendedExercise,
                                           avoiding used: Set<String>,
                                           trainingFacts: TrainingFacts,
                                           coachFacts: CoachFacts,
                                           slot: PlanningSlot,
                                           policy: PlanningConstraintPolicy) -> CoachSession.RecommendedExercise? {
        let originalGroups = groupsCovered(by: exercise)
        guard !originalGroups.isEmpty else { return nil }

        let muscles = muscleIDs(for: exercise)
        let ownPatterns = MovementPattern.patterns(forExerciseNamed: exercise.name,
                                                   primaryMuscles: muscles.primary)
        let trained = CoachSession.trainedExerciseCandidates(facts: coachFacts)
        var pool: [String] = []
        for pattern in ownPatterns.sorted(by: { $0.rawValue < $1.rawValue }) {
            pool.append(contentsOf: trained[pattern] ?? [])
        }
        for pattern in trained.keys.sorted(by: { $0.rawValue < $1.rawValue }) where !ownPatterns.contains(pattern) {
            pool.append(contentsOf: trained[pattern] ?? [])
        }
        pool.append(contentsOf: defaultExerciseNames(for: primarySortGroup(for: exercise)))

        var seen = Set<String>()
        for name in pool where seen.insert(name).inserted {
            guard name != exercise.name, !used.contains(name) else { continue }
            let candidate = CoachSession.RecommendedExercise(name: name)
            guard groupsCovered(by: candidate) == originalGroups else { continue }
            guard isExerciseEligible(candidate, on: slot.date, facts: coachFacts, policy: policy) else { continue }
            // The replacement carries the slot's prescription (sets, RIR) but gets
            // its own bodyweight-aware working range — its rep history is its own.
            let range = CoachSession.repRange(forExerciseNamed: name, facts: coachFacts)
            let ladder = (exercise.sets).map {
                RepLadder.ladder(low: range.lowerBound, high: range.upperBound, sets: $0)
            } ?? exercise.repLadder
            // Build the candidate first: the load lookup reads its rep target, so
            // resolving the load before the ladder would price the wrong reps.
            let replacement = CoachSession.RecommendedExercise(
                name: name,
                sets: exercise.sets,
                repsLow: range.lowerBound,
                repsHigh: range.upperBound,
                rir: exercise.rir,
                repLadder: ladder)
            return CoachSession.RecommendedExercise(
                name: name,
                sets: replacement.sets,
                repsLow: replacement.repsLow,
                repsHigh: replacement.repsHigh,
                loadKg: suggestedLoadKg(for: replacement,
                                        trainingFacts: trainingFacts,
                                        coachFacts: coachFacts),
                rir: replacement.rir,
                repLadder: replacement.repLadder)
        }
        return nil
    }

    private static func plannedSets(for exercise: CoachSession.RecommendedExercise,
                                    deficits: [MuscleGroup: Double],
                                    projected: [MuscleGroup: Double],
                                    experience: ExperienceLevel,
                                    desiredSetsPerExercise: Int,
                                    policy: PlanningConstraintPolicy) -> Int {
        guard !deficits.isEmpty else {
            return min(policy.maxSetsPerExercise, max(2, exercise.sets ?? desiredSetsPerExercise))
        }
        let perSet = PlanAwareWeeklyAccounting.plannedSetsByGroup(from: [copy(exercise, sets: 1)])
        guard perSet.contains(where: { deficits[$0.key] != nil && $0.value > 0 }) else { return 0 }
        var needed = 1
        for (group, amount) in deficits {
            guard let contribution = perSet[group], contribution > 0 else { continue }
            needed = max(needed, Int(ceil(amount / contribution)))
        }

        var safe = policy.maxSetsPerExercise
        if policy.respectsMRVCeiling {
            for (group, contribution) in perSet where contribution > 0 {
                let bands = VolumeLandmarks.bands(for: group, experience: experience)
                let remaining = bands.mrv - (projected[group] ?? 0)
                safe = min(safe, Int(floor(max(0, remaining) / contribution)))
            }
        }

        let desired = max(exercise.sets ?? desiredSetsPerExercise, needed)
        return min(policy.maxSetsPerExercise, max(0, safe), max(1, desired))
    }

    private static func bestExercise(for group: MuscleGroup,
                                      existing: [CoachSession.RecommendedExercise],
                                      facts: TrainingFacts,
                                      coachFacts: CoachFacts,
                                      slot: PlanningSlot,
                                      desiredSetsPerExercise: Int,
                                      policy: PlanningConstraintPolicy) -> CoachSession.RecommendedExercise? {
        let existingOptions = existing
            .filter { groupsCovered(by: $0).contains(group) }
            .filter { isExerciseEligible($0, on: slot.date, facts: coachFacts, policy: policy) }
            .sorted { a, b in
                if coachFacts.recoveryAwareCoachV2 {
                    let pa = coachFacts.recovery.softPenalty(forExerciseNamed: a.name)
                    let pb = coachFacts.recovery.softPenalty(forExerciseNamed: b.name)
                    if pa != pb { return pa < pb }
                }
                return a.name < b.name
            }
        if let first = existingOptions.first {
            return copy(first, sets: first.sets ?? desiredSetsPerExercise,
                        goal: facts.goal, coachFacts: coachFacts, trainingFacts: facts)
        }

        let preferred = CoachSession.mostTrainedExercises(facts: coachFacts)
        for pattern in preferredPatternOrder(for: group) {
            if let name = preferred[pattern],
               groupsCovered(by: CoachSession.RecommendedExercise(name: name)).contains(group) {
                let exercise = CoachSession.RecommendedExercise(name: name)
                if isExerciseEligible(exercise, on: slot.date, facts: coachFacts, policy: policy) {
                    return copy(exercise, sets: desiredSetsPerExercise,
                                goal: facts.goal, coachFacts: coachFacts, trainingFacts: facts)
                }
            }
        }

        return defaultExerciseNames(for: group)
            .map { CoachSession.RecommendedExercise(name: $0) }
            .first { isExerciseEligible($0, on: slot.date, facts: coachFacts, policy: policy) }
            .map { copy($0, sets: desiredSetsPerExercise, goal: facts.goal,
                        coachFacts: coachFacts, trainingFacts: facts) }
    }

    private static func defaultExercises(for deficits: [MuscleGroup: Double],
                                         facts: TrainingFacts,
                                         coachFacts: CoachFacts,
                                         slot: PlanningSlot,
                                         desiredSetsPerExercise: Int,
                                         policy: PlanningConstraintPolicy) -> [CoachSession.RecommendedExercise] {
        deficits.sorted(by: groupDeficitSort).compactMap { group, _ in
            return bestExercise(for: group, existing: [], facts: facts, coachFacts: coachFacts,
                                slot: slot,
                                desiredSetsPerExercise: desiredSetsPerExercise,
                                policy: policy)
        }
    }

    private static func materialize(_ base: CoachSession,
                                    slot: PlanningSlot,
                                    exercises: [CoachSession.RecommendedExercise],
                                    targetedGroups: Set<MuscleGroup>,
                                    synthesized: Bool) -> CoachSession {
        let groups = MuscleGroup.sorted(targetedGroups)
        let title: String
        if groups.isEmpty {
            title = base.title
        } else if groups.count == 1 {
            title = "\(groups[0].displayName) focus"
        } else {
            title = "Strength focus"
        }

        let subtitle: String
        if groups.isEmpty {
            subtitle = base.subtitle
        } else {
            let names = groups.prefix(3).map { $0.displayName.lowercased() }.joined(separator: ", ")
            subtitle = "\(names) volume · \(exercises.reduce(0) { $0 + max(1, $1.sets ?? 3) }) planned sets"
        }

        let idPrefix = synthesized ? "strength.synthetic" : base.id
        return CoachSession(
            id: "\(idPrefix).optimized.\(stableID(slot.id))",
            kind: .strength,
            title: title,
            subtitle: subtitle,
            durationMinutes: max(30, min(60, exercises.reduce(0) { $0 + max(1, $1.sets ?? 3) } * 4)),
            exercises: exercises,
            modality: nil,
            intensity: nil,
            trainingLoadTags: Array(Set(base.trainingLoadTags + ["strength", "planned"])).sorted(),
            citationIds: base.citationIds.isEmpty
                ? CitationRegistry.citationPool(for: .strengthIntensity).citationIds
                : base.citationIds,
            launchPayload: .strengthPlan("optimized.\(stableID(slot.id))"),
            systemsTrained: base.systemsTrained.isEmpty ? [.maximalStrength, .hypertrophy] : base.systemsTrained,
            evidenceCategory: base.evidenceCategory ?? .strengthIntensity)
    }

    private static func syntheticBaseSession() -> CoachSession {
        CoachSession(
            id: "strength.synthetic",
            kind: .strength,
            title: "Strength focus",
            subtitle: "Targeted volume",
            durationMinutes: 45,
            exercises: [],
            trainingLoadTags: ["strength", "planned"],
            citationIds: CitationRegistry.citationPool(for: .strengthIntensity).citationIds,
            launchPayload: .strengthPlan("optimized"),
            systemsTrained: [.maximalStrength, .hypertrophy],
            evidenceCategory: .strengthIntensity)
    }

    private static func remainingStrengthSlots(in plan: WeeklyPlan,
                                               facts: CoachFacts,
                                               schedulePreferences: CoachSchedulePreferences,
                                               policy: PlanningConstraintPolicy,
                                               diagnostics: inout [PlanningDiagnostic]) -> [PlanningSlot] {
        plan.remainingCalendarWeekDays.flatMap { day -> [PlanningSlot] in
            let strengthSessions = day.sessions.filter { $0.kind == .strength }
            guard !strengthSessions.isEmpty else { return [] }
            guard hardStrengthAllowed(on: day.date, facts: facts,
                                      schedulePreferences: schedulePreferences, policy: policy) else {
                diagnostics.append(PlanningDiagnostic(
                    id: "recoveryBlocked.\(day.id)",
                    kind: .recoveryBlocked,
                    message: "Skipped a planned strength slot that was not recovery eligible."))
                return []
            }
            return strengthSessions.map { PlanningSlot(id: $0.id, date: day.date, isExtra: false) }
        }
    }

    private static func extraStrengthSlots(in plan: WeeklyPlan,
                                           existingSlots: [PlanningSlot],
                                           facts: CoachFacts,
                                           schedulePreferences: CoachSchedulePreferences,
                                           policy: PlanningConstraintPolicy,
                                           diagnostics: inout [PlanningDiagnostic]) -> [PlanningSlot] {
        let usedDays = Set(existingSlots.map { Calendar.current.startOfDay(for: $0.date) })
        var extras: [PlanningSlot] = []
        for day in plan.remainingCalendarWeekDays.sorted(by: { $0.date < $1.date }) {
            guard extras.count < policy.maxExtraStrengthSlots else { break }
            let dayStart = Calendar.current.startOfDay(for: day.date)
            guard !usedDays.contains(dayStart), !day.sessions.contains(where: { $0.kind == .strength }) else { continue }
            if policy.respectsRestDays {
                guard !day.sessions.contains(where: { $0.kind == .rest || $0.kind == .recovery }) else {
                    diagnostics.append(PlanningDiagnostic(
                        id: "skippedRest.\(day.id)",
                        kind: .skippedRestDay,
                        message: "Did not add strength work on a rest or recovery day."))
                    continue
                }
            }
            guard hardStrengthAllowed(on: day.date, facts: facts,
                                      schedulePreferences: schedulePreferences, policy: policy) else {
                diagnostics.append(PlanningDiagnostic(
                    id: "extraRecoveryBlocked.\(day.id)",
                    kind: .recoveryBlocked,
                    message: "Did not add extra strength work before recovery eligibility."))
                continue
            }
            extras.append(PlanningSlot(id: "extra-\(day.id)-strength", date: day.date, isExtra: true))
        }
        return extras
    }

    private static func hardStrengthAllowed(on date: Date,
                                            facts: CoachFacts,
                                            schedulePreferences: CoachSchedulePreferences,
                                            policy: PlanningConstraintPolicy) -> Bool {
        let calendar = Calendar.current
        if policy.respectsRestDays,
           isRestDay(date: date, restPreference: schedulePreferences.restPreference, calendar: calendar) {
            return false
        }
        if policy.respectsRecoveryEligibility, let wholeBody = facts.recovery.wholeBody {
            let plannedMidday = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
            if plannedMidday < wholeBody.hardEligibleAt { return false }
        }
        return true
    }

    private static func isExerciseEligible(_ exercise: CoachSession.RecommendedExercise,
                                           on date: Date,
                                           facts: CoachFacts,
                                           policy: PlanningConstraintPolicy) -> Bool {
        guard policy.respectsRecoveryEligibility else { return true }
        let calendar = Calendar.current
        let plannedMidday = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        let muscles = muscleIDs(for: exercise)
        let groups = Set(MuscleGroup.canonicalize(muscles.primary))
            .union(MuscleGroup.canonicalize(muscles.secondary))
        let patterns = MovementPattern.patterns(forExerciseNamed: exercise.name,
                                                primaryMuscles: muscles.primary)

        if let window = facts.recovery.byExercise[exercise.name], plannedMidday < window.hardEligibleAt {
            return false
        }
        for pattern in patterns {
            if let window = facts.recovery.byPattern[pattern], plannedMidday < window.hardEligibleAt {
                return false
            }
        }
        for group in groups {
            if let window = facts.recovery.byGroup[group], plannedMidday < window.hardEligibleAt {
                return false
            }
        }
        return true
    }

    /// The tracked groups that are still under MEV for the week. The candidate
    /// universe is the user's `trackedMuscleGroups` (13 by default), never all 20:
    /// the untracked seven have no catalog depth behind them and would show as
    /// permanent, uncloseable deficits (decision D4).
    private static func weeklyCoverageGroups(in facts: TrainingFacts,
                                             tracked: Set<MuscleGroup>) -> Set<MuscleGroup> {
        let universe = tracked.isEmpty ? MuscleGroup.defaultTracked : tracked
        return universe.filter { group in
            (facts.weeklySetsByGroup[group] ?? 0)
                < VolumeLandmarks.bands(for: group, experience: facts.experience).mev
        }
    }

    /// Which volume landmark the planner aims a group at.
    /// - `.productive`: the MEV→MAV midpoint — the dose the coach *plans toward*
    ///   (issue 1) so small muscles get a productive, not minimum, prescription.
    /// - `.mev`: the minimum effective floor — the threshold used to *report* a
    ///   genuine shortfall (`unresolvedDeficits`) and drive the user-facing nag,
    ///   so the coach only flags a group when it is below the effective minimum,
    ///   never merely short of the aspirational midpoint.
    private enum PlanningTarget {
        case productive
        case mev

        func value(for group: MuscleGroup, experience: ExperienceLevel) -> Double {
            switch self {
            case .productive: return VolumeLandmarks.productiveTarget(for: group, experience: experience)
            case .mev:        return VolumeLandmarks.bands(for: group, experience: experience).mev
            }
        }
    }

    private static func lowDeficits(for groups: Set<MuscleGroup>,
                                    projected: [MuscleGroup: Double],
                                    experience: ExperienceLevel,
                                    target: PlanningTarget = .productive) -> [MuscleGroup: Double] {
        var result: [MuscleGroup: Double] = [:]
        for group in groups {
            let goal = target.value(for: group, experience: experience)
            let sets = projected[group] ?? 0
            if sets < goal {
                result[group] = goal - sets
            }
        }
        return result
    }

    private static func overMRVAmount(projected: [MuscleGroup: Double],
                                      experience: ExperienceLevel) -> Double {
        projected.reduce(0) { total, row in
            let mrv = VolumeLandmarks.bands(for: row.key, experience: experience).mrv
            return total + max(0, row.value - mrv)
        }
    }

    private static func exerciseHelps(_ exercise: CoachSession.RecommendedExercise,
                                      deficits: [MuscleGroup: Double]) -> Bool {
        let groups = groupsCovered(by: exercise)
        return deficits.keys.contains { groups.contains($0) }
    }

    private static func exerciseDeficitScore(_ exercise: CoachSession.RecommendedExercise,
                                             deficits: [MuscleGroup: Double]) -> Double {
        let groups = groupsCovered(by: exercise)
        return deficits.reduce(0) { total, row in
            groups.contains(row.key) ? total + row.value : total
        }
    }

    /// The muscle groups a recommendation earns weekly volume in. Reads the DB++
    /// roles through `PlanAwareWeeklyAccounting.credits(for:)`, so coverage and the
    /// weekly accounting can never disagree about what an exercise trains, and a
    /// non-volume-eligible movement (a stretch, a warm-up drill) covers nothing.
    private static func groupsCovered(by exercise: CoachSession.RecommendedExercise) -> Set<MuscleGroup> {
        Set(PlanAwareWeeklyAccounting.credits(for: exercise).keys)
    }

    private static func primarySortGroup(for exercise: CoachSession.RecommendedExercise) -> MuscleGroup {
        let muscles = muscleIDs(for: exercise)
        return MuscleGroup.canonicalize(muscles.primary)
            .min { MuscleGroup.canonicalIndex($0) < MuscleGroup.canonicalIndex($1) }
            ?? MuscleGroup.sorted(groupsCovered(by: exercise)).first
            ?? .abdominals
    }

    private static func muscleIDs(for exercise: CoachSession.RecommendedExercise) -> (primary: [String], secondary: [String]) {
        if !exercise.primaryMuscles.isEmpty {
            return (exercise.primaryMuscles, [])
        }
        if let template = ExerciseLibrary.byName[exercise.name.lowercased()] {
            return (template.primaryMuscles, template.secondaryMuscles)
        }
        if let cat = ExerciseCategory.guess(fromName: exercise.name) {
            return (MuscleGroup.defaults(forCategory: cat).map(\.rawValue), [])
        }
        return ([], [])
    }

    private static func copy(_ exercise: CoachSession.RecommendedExercise,
                             sets: Int? = nil,
                             goal: TrainingGoal? = nil,
                             coachFacts: CoachFacts? = nil,
                             trainingFacts: TrainingFacts? = nil) -> CoachSession.RecommendedExercise {
        let resolvedSets = sets ?? exercise.sets
        // Working range is bodyweight-aware (issue: 12/10/8 crunches): for a
        // bodyweight/high-rep movement it tracks the user's real logged reps —
        // or a high-rep default absent history — instead of the goal's loaded
        // range. Weighted lifts keep the goal's range unchanged.
        let range: ClosedRange<Int>? = goal.map { g in
            PrescriptionMath.repRange(
                forExerciseNamed: exercise.name, goal: g,
                recentTopReps: coachFacts.flatMap {
                    CoachSession.recentTopReps(forExerciseNamed: exercise.name, facts: $0)
                })
        }
        let bodyweightAdjusted = goal != nil && range != goal?.repRange
        // Regenerate the descending rep ladder for the resolved set count so the
        // planner's reshaping keeps a productive pyramid (issue 2). Falls back to
        // the exercise's existing ladder when no goal is known.
        let ladder: [Int]?
        if let range, let count = resolvedSets, count > 0 {
            ladder = RepLadder.ladder(low: range.lowerBound, high: range.upperBound, sets: count)
        } else {
            ladder = exercise.repLadder
        }
        return CoachSession.RecommendedExercise(
            name: exercise.name,
            primaryMuscles: exercise.primaryMuscles,
            sets: resolvedSets,
            repsLow: bodyweightAdjusted ? range?.lowerBound : (exercise.repsLow ?? range?.lowerBound),
            repsHigh: bodyweightAdjusted ? range?.upperBound : (exercise.repsHigh ?? range?.upperBound),
            loadKg: exercise.loadKg ?? suggestedLoadKg(for: exercise,
                                                       trainingFacts: trainingFacts,
                                                       coachFacts: coachFacts),
            rir: exercise.rir ?? goal?.targetRIR,
            repLadder: ladder)
    }

    /// Planned previews should carry a useful, history-based load whenever the
    /// user has trained that movement before. New or bodyweight movements remain
    /// unweighted instead of inventing a number.
    private static func suggestedLoadKg(for exercise: CoachSession.RecommendedExercise,
                                        trainingFacts: TrainingFacts?,
                                        coachFacts: CoachFacts?) -> Double? {
        // A bodyweight movement genuinely has no external load — never invent one.
        guard !ExerciseLoading.isBodyweight(named: exercise.name) else { return nil }

        let reps = exercise.repLadder?.first ?? exercise.repsLow

        // 1. Trailing-week snapshot (unchanged behaviour, keeps existing tests green).
        if let facts = trainingFacts,
           let snapshot = facts.liftSnapshots.first(where: {
               $0.key.caseInsensitiveCompare(exercise.name) == .orderedSame
           })?.value,
           snapshot.bestE1RM > 0 {
            let r = reps ?? snapshot.topSetReps
            if r > 0, let load = load(fromE1RM: snapshot.bestE1RM, reps: r) { return load }
        }

        // 2. All-history fallback: `liftSnapshots` only covers the trailing week,
        //    so anything trained 8+ days ago used to render as BW (field test
        //    2026-08-18 #2).
        if let coachFacts,
           let top = CoachSession.recentTopSet(forExerciseNamed: exercise.name, facts: coachFacts),
           top.bestE1RM > 0 {
            let r = reps ?? top.reps
            if r > 0, let load = load(fromE1RM: top.bestE1RM, reps: r) { return load }
        }
        return nil
    }

    /// Inverse-e1RM at the planned rep target, rounded to the nearest half unit.
    private static func load(fromE1RM e1rm: Double, reps: Int) -> Double? {
        let suggested = WeightSuggestion.inverseE1RM(e1rm: e1rm, reps: reps, formula: .epley)
        return suggested > 0 ? (suggested * 2).rounded() / 2 : nil
    }

    /// Catalog fallbacks per muscle group, in descending preference. Each list
    /// leads with the compound the group is most reliably trained by, so the
    /// planner's last resort is still a defensible prescription. Every name here
    /// must resolve in `ExerciseLibrary.starter`.
    private static func defaultExerciseNames(for group: MuscleGroup) -> [String] {
        switch group {
        case .quadriceps: return ["Back Squat", "Leg Press", "Front Squat"]
        case .hamstrings: return ["Romanian Deadlift", "Lying Leg Curl", "Deadlift"]
        case .glutes: return ["Hip Thrust", "Back Squat", "Romanian Deadlift"]
        case .lats: return ["Lat Pulldown", "Pull-Up", "Barbell Row"]
        case .middleBack: return ["Seated Cable Row", "Barbell Row", "Dumbbell Row"]
        case .lowerBack: return ["Back Extension", "Deadlift", "Romanian Deadlift"]
        case .traps: return ["Barbell Shrug", "Dumbbell Shrug", "Deadlift"]
        case .chest: return ["Bench Press", "Dumbbell Bench Press", "Machine Chest Press"]
        case .shoulders: return ["Overhead Press", "Dumbbell Lateral Raise", "Machine Shoulder Press"]
        case .biceps: return ["Barbell Curl", "Dumbbell Curl", "Lat Pulldown"]
        case .triceps: return ["Triceps Pushdown", "Overhead Cable Extension", "Close-Grip Bench Press"]
        case .forearms: return ["Wrist Curl", "Farmer's Walk", "Barbell Shrug"]
        case .abdominals: return ["Cable Crunch", "Plank", "Hanging Leg Raise"]
        case .calves: return ["Standing Calf Raise", "Seated Calf Raise", "Calf Press on Leg Press"]
        case .tibialis: return ["Standing Calf Raise", "Seated Calf Raise"]
        case .adductors: return ["Thigh Adductor", "Front Squat", "Leg Press"]
        case .abductors: return ["Thigh Abductor", "Hip Thrust"]
        case .hipFlexors: return ["Hanging Leg Raise", "Plank"]
        case .neck: return ["Neck Flexion", "Barbell Shrug"]
        case .rotatorCuff: return ["Cable External Rotation", "Dumbbell Lateral Raise"]
        }
    }

    private static func preferredPatternOrder(for group: MuscleGroup) -> [MovementPattern] {
        switch group {
        case .quadriceps: return [.squat, .hinge]
        case .hamstrings, .glutes, .lowerBack: return [.hinge, .squat]
        case .lats: return [.verticalPull, .horizontalPull]
        case .middleBack, .traps: return [.horizontalPull, .verticalPull, .hinge]
        case .chest: return [.horizontalPush]
        case .shoulders, .rotatorCuff: return [.verticalPush, .horizontalPush]
        case .biceps: return [.verticalPull, .horizontalPull]
        case .triceps: return [.horizontalPush, .verticalPush]
        case .forearms: return [.carry, .horizontalPull]
        case .calves, .tibialis: return [.locomotion, .squat]
        case .abdominals, .hipFlexors: return [.core, .carry]
        case .adductors, .abductors: return [.squat, .hinge]
        case .neck: return [.horizontalPull]
        }
    }

    private static func uniqueStrengthCandidates(_ sessions: [CoachSession]) -> [CoachSession] {
        var seen = Set<String>()
        return sessions
            .filter { $0.kind == .strength && !($0.exercises ?? []).isEmpty }
            .filter { seen.insert($0.id).inserted }
            .sorted { a, b in
                if a.id != b.id { return a.id < b.id }
                return a.title < b.title
            }
    }

    private static func groupDeficitSort(_ lhs: (key: MuscleGroup, value: Double),
                                         _ rhs: (key: MuscleGroup, value: Double)) -> Bool {
        if lhs.value != rhs.value { return lhs.value > rhs.value }
        return MuscleGroup.canonicalIndex(lhs.key) < MuscleGroup.canonicalIndex(rhs.key)
    }

    private static func stableID(_ value: String) -> String {
        value
            .lowercased()
            .map { ch -> Character in
                ch.isLetter || ch.isNumber ? ch : "."
            }
            .reduce(into: "") { result, ch in
                if ch == ".", result.last == "." { return }
                result.append(ch)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func isRestDay(date: Date, restPreference: RestPreference,
                                  calendar: Calendar) -> Bool {
        switch restPreference {
        case .fixed(let days):
            guard let weekday = Weekday(from: date, calendar: calendar) else { return false }
            return days.contains(weekday)
        case .rolling(let everyNDays):
            let weekStart = WeeklyStats.weekStart(now: date)
            let daysSinceWeekStart = calendar.dateComponents([.day], from: weekStart, to: date).day ?? 0
            let cycleLength = everyNDays + 1
            return daysSinceWeekStart > 0 && (daysSinceWeekStart % cycleLength) == everyNDays
        }
    }
}
