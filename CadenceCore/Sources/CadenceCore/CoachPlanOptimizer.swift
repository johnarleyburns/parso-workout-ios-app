import Foundation

public struct OptimizedCoachPlan: Sendable, Equatable {
    public let plannedStrengthSessions: [CoachSession]
    public let unresolvedDeficits: [BodyPart: Double]
    public let diagnostics: [PlanningDiagnostic]

    public init(plannedStrengthSessions: [CoachSession],
                unresolvedDeficits: [BodyPart: Double] = [:],
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
    public let part: BodyPart?
    public let value: Double?

    public init(id: String, kind: Kind, message: String,
                part: BodyPart? = nil, value: Double? = nil) {
        self.id = id
        self.kind = kind
        self.message = message
        self.part = part
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
        let remainingDeficits: [BodyPart: Double]
        let score: CandidateScore
    }

    private struct CandidateScore: Comparable {
        let remainingParts: Int
        let remainingMagnitude: Double
        let totalSets: Int
        let overMRV: Double
        let unfamiliarExercises: Int
        let sessionID: String

        static func < (lhs: CandidateScore, rhs: CandidateScore) -> Bool {
            if lhs.remainingParts != rhs.remainingParts { return lhs.remainingParts < rhs.remainingParts }
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
        let lowParts = weeklyCoverageParts(in: trainingFacts, excluded: schedulePreferences.excludedCoverageParts)
        let strengthCandidates = uniqueStrengthCandidates(candidateSessions)
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

        var projected = trainingFacts.weeklySetsByPart
        var planned: [CoachSession] = []
        var deficits = lowDeficits(for: lowParts, projected: projected, experience: trainingFacts.experience)

        plan(slots: slots,
             into: &planned,
             projected: &projected,
             deficits: &deficits,
             lowParts: lowParts,
             trainingFacts: trainingFacts,
             coachFacts: coachFacts,
             strengthCandidates: strengthCandidates,
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
                 lowParts: lowParts,
                 trainingFacts: trainingFacts,
                 coachFacts: coachFacts,
                 strengthCandidates: strengthCandidates,
                 policy: constraintPolicy,
                 diagnostics: &diagnostics)
        }

        for (part, value) in deficits.sorted(by: partDeficitSort) {
            diagnostics.append(PlanningDiagnostic(
                id: "unresolved.\(part.rawValue)",
                kind: .unresolvedDeficit,
                message: "\(part.displayName) remains \(Format.sets(value)) sets below the starting range after safe planned work.",
                part: part,
                value: value))
        }

        return OptimizedCoachPlan(
            plannedStrengthSessions: planned,
            unresolvedDeficits: deficits,
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

    /// Lower-body parts; everything else (except abs, treated as neutral core) is
    /// considered upper body for split classification.
    private static let lowerBodyParts: Set<BodyPart> = [.legs, .calves]

    /// Classify a strength session by the body parts its exercises cover. Non-strength
    /// or exercise-less sessions return `nil` (no structure to explain).
    public static func classifyStructure(of session: CoachSession) -> SessionStructure? {
        guard session.kind == .strength, let exercises = session.exercises, !exercises.isEmpty else {
            return nil
        }
        let parts = coveredParts(of: session)
        guard !parts.isEmpty else { return nil }
        if parts.count >= 5 { return .fullBody }
        let lower = parts.intersection(lowerBodyParts)
        let upper = parts.subtracting(lowerBodyParts).subtracting([.abs])
        if upper.isEmpty && !lower.isEmpty { return .lowerFocus }
        if lower.isEmpty && upper.count >= 2 { return .upperFocus }
        return .focused
    }

    /// Build the user-facing, cited `ObservedFact` explaining a session's structure.
    public static func sessionStructureFact(for session: CoachSession, now: Date) -> ObservedFact? {
        guard let structure = classifyStructure(of: session) else { return nil }
        let parts = coveredParts(of: session)
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
            let names = parts.sorted { partIndex($0) < partIndex($1) }
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

    private static func coveredParts(of session: CoachSession) -> Set<BodyPart> {
        (session.exercises ?? []).reduce(into: Set<BodyPart>()) { acc, exercise in
            acc.formUnion(partsCovered(by: exercise))
        }
    }

    private static func plan(slots: [PlanningSlot],
                              into planned: inout [CoachSession],
                              projected: inout [BodyPart: Double],
                              deficits: inout [BodyPart: Double],
                              lowParts: Set<BodyPart>,
                              trainingFacts: TrainingFacts,
                              coachFacts: CoachFacts,
                              strengthCandidates: [CoachSession],
                              policy: PlanningConstraintPolicy,
                              diagnostics: inout [PlanningDiagnostic]) {
        for (i, slot) in slots.enumerated() {
            let slotsLeft = slots.count - i
            let slotDeficits: [BodyPart: Double] = deficits.mapValues { ceil($0 / Double(slotsLeft)) }
            let choice = chooseSession(
                for: slot,
                deficits: slotsLeft > 1 ? slotDeficits : deficits,
                projected: projected,
                trainingFacts: trainingFacts,
                coachFacts: coachFacts,
                strengthCandidates: strengthCandidates,
                policy: policy)
            planned.append(choice.session)
            let added = PlanAwareWeeklyAccounting.plannedSetsByPart(from: [choice.session])
            projected = projected.merging(added) { $0 + $1 }
            deficits = lowDeficits(for: lowParts, projected: projected, experience: trainingFacts.experience)

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
                                      deficits: [BodyPart: Double],
                                      projected: [BodyPart: Double],
                                      trainingFacts: TrainingFacts,
                                      coachFacts: CoachFacts,
                                      strengthCandidates: [CoachSession],
                                      policy: PlanningConstraintPolicy) -> CandidatePlan {
        let candidatePool = strengthCandidates.isEmpty ? [syntheticBaseSession()] : strengthCandidates
        let options = candidatePool.map {
            optimizedVersion(of: $0,
                             slot: slot,
                             deficits: deficits,
                             projected: projected,
                             trainingFacts: trainingFacts,
                             coachFacts: coachFacts,
                             policy: policy)
        } + [
            optimizedVersion(of: syntheticBaseSession(),
                             slot: slot,
                             deficits: deficits,
                             projected: projected,
                             trainingFacts: trainingFacts,
                             coachFacts: coachFacts,
                             policy: policy)
        ]

        return options.min { $0.score < $1.score } ?? CandidatePlan(
            session: materialize(syntheticBaseSession(), slot: slot,
                                 exercises: defaultExercises(for: deficits,
                                                             facts: trainingFacts,
                                                             coachFacts: coachFacts,
                                                             slot: slot,
                                                             policy: policy),
                                 targetedParts: Set(deficits.keys), synthesized: true),
            remainingDeficits: deficits,
            score: CandidateScore(remainingParts: deficits.count,
                                  remainingMagnitude: deficits.values.reduce(0, +),
                                  totalSets: 0,
                                  overMRV: 0,
                                  unfamiliarExercises: 0,
                                  sessionID: "strength.synthetic"))
    }

    private static func optimizedVersion(of base: CoachSession,
                                         slot: PlanningSlot,
                                         deficits: [BodyPart: Double],
                                         projected: [BodyPart: Double],
                                         trainingFacts: TrainingFacts,
                                         coachFacts: CoachFacts,
                                         policy: PlanningConstraintPolicy) -> CandidatePlan {
        let originalNames = Set((base.exercises ?? []).map(\.name))
        let exercises = reshapedExercises(from: base.exercises ?? [],
                                          deficits: deficits,
                                          projected: projected,
                                          trainingFacts: trainingFacts,
                                          coachFacts: coachFacts,
                                          slot: slot,
                                          policy: policy)
        let added = PlanAwareWeeklyAccounting.plannedSetsByPart(from: exercises)
        let nextProjected = projected.merging(added) { $0 + $1 }
        let remaining = lowDeficits(for: Set(deficits.keys),
                                    projected: nextProjected,
                                    experience: trainingFacts.experience)
        let totalSets = exercises.reduce(0) { $0 + max(1, $1.sets ?? 3) }
        let unfamiliar = exercises.filter { !originalNames.contains($0.name) }.count
        let session = materialize(base,
                                  slot: slot,
                                  exercises: exercises,
                                  targetedParts: Set(deficits.keys),
                                  synthesized: base.id == syntheticBaseSession().id)
        let score = CandidateScore(
            remainingParts: remaining.count,
            remainingMagnitude: remaining.values.reduce(0, +),
            totalSets: totalSets,
            overMRV: overMRVAmount(projected: nextProjected, experience: trainingFacts.experience),
            unfamiliarExercises: unfamiliar,
            sessionID: session.id)
        return CandidatePlan(session: session, remainingDeficits: remaining, score: score)
    }

    private static func reshapedExercises(from baseExercises: [CoachSession.RecommendedExercise],
                                          deficits: [BodyPart: Double],
                                          projected: [BodyPart: Double],
                                          trainingFacts: TrainingFacts,
                                          coachFacts: CoachFacts,
                                          slot: PlanningSlot,
                                          policy: PlanningConstraintPolicy) -> [CoachSession.RecommendedExercise] {
        guard !deficits.isEmpty else {
            let preserved = baseExercises
                .filter { isExerciseEligible($0, on: slot.date, facts: coachFacts, policy: policy) }
                .prefix(policy.maxExercisesPerSession)
                .map { exercise in
                    copy(exercise,
                         sets: min(policy.maxSetsPerExercise, max(1, exercise.sets ?? 3)),
                         goal: trainingFacts.goal)
                }
            if !preserved.isEmpty { return Array(preserved) }
            return ["Back Squat", "Bench Press", "Barbell Row", "Romanian Deadlift"]
                .map { CoachSession.RecommendedExercise(name: $0, sets: 3) }
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

        for exercise in usefulBase {
            guard selected.count < policy.maxExercisesPerSession else { break }
            guard isExerciseEligible(exercise, on: slot.date, facts: coachFacts, policy: policy) else { continue }
            let sets = plannedSets(for: exercise,
                                   deficits: lowDeficits(for: Set(deficits.keys),
                                                         projected: runningProjected,
                                                         experience: trainingFacts.experience),
                                   projected: runningProjected,
                                   experience: trainingFacts.experience,
                                   policy: policy)
            guard sets > 0, sessionSets + sets <= policy.maxTotalSetsPerSession else { continue }
            let planned = copy(exercise, sets: sets, goal: trainingFacts.goal)
            selected.append(planned)
            sessionSets += sets
            runningProjected = runningProjected.merging(
                PlanAwareWeeklyAccounting.plannedSetsByPart(from: [planned])) { $0 + $1 }
        }

        var remaining = lowDeficits(for: Set(deficits.keys),
                                    projected: runningProjected,
                                    experience: trainingFacts.experience)
        while !remaining.isEmpty,
              selected.count < policy.maxExercisesPerSession,
              sessionSets < policy.maxTotalSetsPerSession {
            guard let part = remaining.sorted(by: partDeficitSort).first?.key,
                  let next = bestExercise(for: part,
                                          existing: selected + baseExercises,
                                          facts: trainingFacts,
                                          coachFacts: coachFacts,
                                          slot: slot,
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
                                   policy: policy)
            guard sets > 0, sessionSets + sets <= policy.maxTotalSetsPerSession else { break }
            let planned = copy(next, sets: sets, goal: trainingFacts.goal)
            selected.append(planned)
            sessionSets += sets
            runningProjected = runningProjected.merging(
                PlanAwareWeeklyAccounting.plannedSetsByPart(from: [planned])) { $0 + $1 }
            remaining = lowDeficits(for: Set(deficits.keys),
                                    projected: runningProjected,
                                    experience: trainingFacts.experience)
        }

        if selected.isEmpty {
            let fallback = defaultExercises(for: deficits,
                                            facts: trainingFacts,
                                            coachFacts: coachFacts,
                                            slot: slot,
                                            policy: policy)
                .filter { isExerciseEligible($0, on: slot.date, facts: coachFacts, policy: policy) }
                .prefix(policy.maxExercisesPerSession)
            selected = Array(fallback)
        }

        return selected.sorted { a, b in
            let apart = primarySortPart(for: a)
            let bpart = primarySortPart(for: b)
            if apart != bpart { return partIndex(apart) < partIndex(bpart) }
            return a.name < b.name
        }
    }

    private static func plannedSets(for exercise: CoachSession.RecommendedExercise,
                                    deficits: [BodyPart: Double],
                                    projected: [BodyPart: Double],
                                    experience: ExperienceLevel,
                                    policy: PlanningConstraintPolicy) -> Int {
        guard !deficits.isEmpty else { return min(policy.maxSetsPerExercise, max(2, exercise.sets ?? 3)) }
        let perSet = PlanAwareWeeklyAccounting.plannedSetsByPart(from: [copy(exercise, sets: 1)])
        guard perSet.contains(where: { deficits[$0.key] != nil && $0.value > 0 }) else { return 0 }

        var needed = 1
        for (part, amount) in deficits {
            guard let contribution = perSet[part], contribution > 0 else { continue }
            needed = max(needed, Int(ceil(amount / contribution)))
        }

        var safe = policy.maxSetsPerExercise
        if policy.respectsMRVCeiling {
            for (part, contribution) in perSet where contribution > 0 {
                let bands = VolumeLandmarks.bands(for: part, experience: experience)
                let remaining = bands.mrv - (projected[part] ?? 0)
                safe = min(safe, Int(floor(max(0, remaining) / contribution)))
            }
        }

        let desired = max(exercise.sets ?? 0, needed)
        return min(policy.maxSetsPerExercise, max(0, safe), max(1, desired))
    }

    private static func bestExercise(for part: BodyPart,
                                     existing: [CoachSession.RecommendedExercise],
                                     facts: TrainingFacts,
                                     coachFacts: CoachFacts,
                                     slot: PlanningSlot,
                                     policy: PlanningConstraintPolicy) -> CoachSession.RecommendedExercise? {
        let existingOptions = existing
            .filter { partsCovered(by: $0).contains(part) }
            .filter { isExerciseEligible($0, on: slot.date, facts: coachFacts, policy: policy) }
            .sorted { $0.name < $1.name }
        if let first = existingOptions.first {
            return copy(first, sets: nil, goal: facts.goal)
        }

        let preferred = CoachSession.mostTrainedExercises(facts: coachFacts)
        for pattern in preferredPatternOrder(for: part) {
            if let name = preferred[pattern],
               partsCovered(by: CoachSession.RecommendedExercise(name: name)).contains(part) {
                let exercise = CoachSession.RecommendedExercise(name: name)
                if isExerciseEligible(exercise, on: slot.date, facts: coachFacts, policy: policy) {
                    return copy(exercise, sets: nil, goal: facts.goal)
                }
            }
        }

        return defaultExerciseNames(for: part)
            .map { CoachSession.RecommendedExercise(name: $0) }
            .first { isExerciseEligible($0, on: slot.date, facts: coachFacts, policy: policy) }
            .map { copy($0, sets: nil, goal: facts.goal) }
    }

    private static func defaultExercises(for deficits: [BodyPart: Double],
                                         facts: TrainingFacts,
                                         coachFacts: CoachFacts,
                                         slot: PlanningSlot,
                                         policy: PlanningConstraintPolicy) -> [CoachSession.RecommendedExercise] {
        deficits.sorted(by: partDeficitSort).compactMap { part, _ in
            return bestExercise(for: part, existing: [], facts: facts, coachFacts: coachFacts,
                                slot: slot, policy: policy)
        }
    }

    private static func materialize(_ base: CoachSession,
                                    slot: PlanningSlot,
                                    exercises: [CoachSession.RecommendedExercise],
                                    targetedParts: Set<BodyPart>,
                                    synthesized: Bool) -> CoachSession {
        let parts = targetedParts.sorted { partIndex($0) < partIndex($1) }
        let title: String
        if parts.isEmpty {
            title = base.title
        } else if parts.count == 1 {
            title = "\(parts[0].displayName) focus"
        } else {
            title = "Strength focus"
        }

        let subtitle: String
        if parts.isEmpty {
            subtitle = base.subtitle
        } else {
            let names = parts.prefix(3).map { $0.displayName.lowercased() }.joined(separator: ", ")
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
        let primaryParts = BodyPart.parts(forMuscleIDs: muscles.primary)
        let secondaryParts = BodyPart.parts(forMuscleIDs: muscles.secondary)
        let bodyParts = primaryParts.union(secondaryParts)
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
        for part in bodyParts {
            if let window = facts.recovery.byBodyPart[part], plannedMidday < window.hardEligibleAt {
                return false
            }
        }
        return true
    }

    private static func weeklyCoverageParts(in facts: TrainingFacts,
                                            excluded: Set<BodyPart> = []) -> Set<BodyPart> {
        Set(BodyPart.allCases.filter { part in
            guard !excluded.contains(part) else { return false }
            return (facts.weeklySetsByPart[part] ?? 0) < VolumeLandmarks.bands(for: part, experience: facts.experience).mev
        })
    }

    private static func lowDeficits(for parts: Set<BodyPart>,
                                    projected: [BodyPart: Double],
                                    experience: ExperienceLevel) -> [BodyPart: Double] {
        var result: [BodyPart: Double] = [:]
        for part in parts {
            let target = VolumeLandmarks.bands(for: part, experience: experience).mev
            let sets = projected[part] ?? 0
            if sets < target {
                result[part] = target - sets
            }
        }
        return result
    }

    private static func overMRVAmount(projected: [BodyPart: Double],
                                      experience: ExperienceLevel) -> Double {
        BodyPart.allCases.reduce(0) { total, part in
            let mrv = VolumeLandmarks.bands(for: part, experience: experience).mrv
            return total + max(0, (projected[part] ?? 0) - mrv)
        }
    }

    private static func exerciseHelps(_ exercise: CoachSession.RecommendedExercise,
                                      deficits: [BodyPart: Double]) -> Bool {
        let parts = partsCovered(by: exercise)
        return deficits.keys.contains { parts.contains($0) }
    }

    private static func exerciseDeficitScore(_ exercise: CoachSession.RecommendedExercise,
                                             deficits: [BodyPart: Double]) -> Double {
        let parts = partsCovered(by: exercise)
        return deficits.reduce(0) { total, row in
            parts.contains(row.key) ? total + row.value : total
        }
    }

    private static func partsCovered(by exercise: CoachSession.RecommendedExercise) -> Set<BodyPart> {
        let muscles = muscleIDs(for: exercise)
        let primary = BodyPart.parts(forMuscleIDs: muscles.primary)
            .union(BodyPart.parts(forMuscleIDs: muscles.secondary))
        if primary.isEmpty, !exercise.name.isEmpty {
            if let template = ExerciseLibrary.byName[exercise.name.lowercased()] {
                return BodyPart.parts(forMuscleIDs: template.primaryMuscles)
                    .union(BodyPart.parts(forMuscleIDs: template.secondaryMuscles))
            }
            if let cat = BodyPart.guessCategory(from: exercise.name) {
                return BodyPart.parts(forCategory: cat)
            }
        }
        return primary
    }

    private static func primarySortPart(for exercise: CoachSession.RecommendedExercise) -> BodyPart {
        let muscles = muscleIDs(for: exercise)
        return BodyPart.parts(forMuscleIDs: muscles.primary)
            .sorted { partIndex($0) < partIndex($1) }
            .first ?? .abs
    }

    private static func muscleIDs(for exercise: CoachSession.RecommendedExercise) -> (primary: [String], secondary: [String]) {
        if !exercise.primaryMuscles.isEmpty {
            return (exercise.primaryMuscles, [])
        }
        if let template = ExerciseLibrary.byName[exercise.name.lowercased()] {
            return (template.primaryMuscles, template.secondaryMuscles)
        }
        if let cat = BodyPart.guessCategory(from: exercise.name) {
            return (BodyPart.defaultMuscles(forCategory: cat), [])
        }
        return ([], [])
    }

    private static func copy(_ exercise: CoachSession.RecommendedExercise,
                             sets: Int? = nil,
                             goal: TrainingGoal? = nil) -> CoachSession.RecommendedExercise {
        let range = goal?.repRange
        let resolvedSets = sets ?? exercise.sets
        // Regenerate the descending rep ladder for the resolved set count so the
        // planner's reshaping keeps a productive pyramid (issue 2). Falls back to
        // the exercise's existing ladder when no goal is known.
        let ladder: [Int]?
        if let goal, let count = resolvedSets, count > 0 {
            ladder = RepLadder.ladder(for: goal, sets: count)
        } else {
            ladder = exercise.repLadder
        }
        return CoachSession.RecommendedExercise(
            name: exercise.name,
            primaryMuscles: exercise.primaryMuscles,
            sets: resolvedSets,
            repsLow: exercise.repsLow ?? range?.lowerBound,
            repsHigh: exercise.repsHigh ?? range?.upperBound,
            loadKg: exercise.loadKg,
            rir: exercise.rir ?? goal?.targetRIR,
            repLadder: ladder)
    }

    private static func defaultExerciseNames(for part: BodyPart) -> [String] {
        switch part {
        case .legs: return ["Back Squat", "Leg Press", "Romanian Deadlift"]
        case .back: return ["Barbell Row", "Lat Pulldown", "Seated Cable Row"]
        case .chest: return ["Bench Press", "Dumbbell Bench Press", "Machine Chest Press"]
        case .shoulders: return ["Overhead Press", "Dumbbell Lateral Raise", "Machine Shoulder Press"]
        case .biceps: return ["Barbell Curl", "Dumbbell Curl", "Lat Pulldown"]
        case .triceps: return ["Triceps Pushdown", "Overhead Cable Extension", "Close-Grip Bench Press"]
        case .calves: return ["Standing Calf Raise", "Seated Calf Raise", "Calf Press on Leg Press"]
        case .abs: return ["Cable Crunch", "Plank", "Hanging Leg Raise"]
        }
    }

    private static func preferredPatternOrder(for part: BodyPart) -> [MovementPattern] {
        switch part {
        case .legs: return [.squat, .hinge]
        case .back: return [.horizontalPull, .verticalPull, .hinge]
        case .chest: return [.horizontalPush]
        case .shoulders: return [.verticalPush, .horizontalPush]
        case .biceps: return [.verticalPull, .horizontalPull]
        case .triceps: return [.horizontalPush, .verticalPush]
        case .calves: return [.locomotion, .squat]
        case .abs: return [.core, .carry]
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

    private static func partDeficitSort(_ lhs: (key: BodyPart, value: Double),
                                        _ rhs: (key: BodyPart, value: Double)) -> Bool {
        if lhs.value != rhs.value { return lhs.value > rhs.value }
        return partIndex(lhs.key) < partIndex(rhs.key)
    }

    private static func partIndex(_ part: BodyPart) -> Int {
        BodyPart.allCases.firstIndex(of: part) ?? Int.max
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
