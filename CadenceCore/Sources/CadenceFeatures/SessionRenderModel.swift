import Foundation
import CadenceCore

/// Per-render snapshot of everything `SessionView` needs to render exercise
/// cards without scanning SwiftData on every keystroke. An `Equatable Signature`
/// gates rebuilds; identical signatures skip the work.
public enum SessionRenderModel {

    /// Compact, collapsed-card copy. It intentionally contains no editing
    /// affordances; the disclosure control is the only collapsed interaction.
    ///
    /// With partners the combined `6/6 sets` line is dropped in favour of one
    /// per-performer prior-session segment (`Me: …; Sam: …`, owner first, roster
    /// order); a performer with no prior sets contributes nothing, and when
    /// nobody has history the counts summary returns so the card is never blank
    /// (field test 2026-08-20 issue 2, decision D5).
    public static func compactSummary(context: ExerciseContext,
                                      unit: MeasurementUnitPreference) -> String {
        guard context.hasPartners else {
            return countsSummary(context: context, unit: unit)
        }
        let segments = context.performerContexts.compactMap {
            lastTimeSegment(label: $0.label, sets: $0.lastTimeSets, unit: unit)
        }
        guard !segments.isEmpty else {
            return countsSummary(context: context, unit: unit)
        }
        return segments.joined(separator: "; ")
    }

    /// The combined `6/6 sets · reps · weight · BW` summary, used solo and as
    /// the fallback when no partner performer has prior-session history.
    private static func countsSummary(context: ExerciseContext,
                                      unit: MeasurementUnitPreference) -> String {
        let completed = context.sets.filter { !$0.isWarmup }.count
        let planned = completed + context.pendingSets.count
        var parts = ["\(completed)/\(max(completed, planned)) sets"]
        let reps = (context.sets.filter { !$0.isWarmup }.map(\.reps) + context.pendingSets.map(\.targetReps)).filter { $0 > 0 }
        if let minReps = reps.min(), let maxReps = reps.max() {
            parts.append(minReps == maxReps ? "\(minReps) reps" : "\(minReps)–\(maxReps) reps")
        }
        let weights = context.sets.filter { !$0.isWarmup && !$0.usesBodyweight }.map(\.weight) +
            context.pendingSets.compactMap(\.targetWeightKg)
        if !weights.isEmpty, let minWeight = weights.min(), let maxWeight = weights.max() {
            let low = Format.weight(minWeight, unit: unit)
            let high = Format.weight(maxWeight, unit: unit)
            parts.append(low == high ? low : "\(low)–\(high)")
        } else if context.sets.contains(where: { !$0.isWarmup && $0.usesBodyweight }) {
            parts.append("BW")
        }
        let partners = context.performerContexts.filter { !$0.isMe }.map(\.label)
        if !partners.isEmpty { parts.append(partners.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    /// One performer's collapsed "last time" segment, e.g. `Me: 185 lb × 5, 190 lb × 6`.
    /// `nil` when the performer has no prior-session sets — never a fake 0.
    public static func lastTimeSegment(label: String, sets: [SetDisplay],
                                       unit: MeasurementUnitPreference) -> String? {
        guard !sets.isEmpty else { return nil }
        return "\(label): " + sets.map { setLineText($0, unit: unit) }.joined(separator: ", ")
    }

    /// One prior set as text, shared by the collapsed and expanded cards and the
    /// set editor: `180 lb × 8`, `BW × 12`, `BW + 10 kg × 12`.
    public static func setLineText(_ set: SetDisplay, unit: MeasurementUnitPreference) -> String {
        if set.usesBodyweight {
            let added = set.weight > 0 ? " + \(Format.weightValue(set.weight, unit: unit)) \(unit.abbreviation)" : ""
            return "BW\(added) × \(set.reps)"
        }
        return "\(Format.weightValue(set.weight, unit: unit)) \(unit.abbreviation) × \(set.reps)"
    }

    /// A single set as displayed in a completed set row.
    public struct SetDisplay: Equatable, Identifiable {
        public var id: UUID { setID }
        public var setID: UUID
        public var weight: Double
        public var reps: Int
        public var rpe: Double?
        public var isWarmup: Bool
        public var usesBodyweight: Bool
        public var isOwnerSet: Bool
        public var performedBy: PerformerRef?
        public var isAllTimePR: Bool

        public init(setID: UUID, weight: Double, reps: Int, rpe: Double?, isWarmup: Bool,
                    usesBodyweight: Bool, isOwnerSet: Bool, performedBy: PerformerRef?,
                    isAllTimePR: Bool) {
            self.setID = setID
            self.weight = weight
            self.reps = reps
            self.rpe = rpe
            self.isWarmup = isWarmup
            self.usesBodyweight = usesBodyweight
            self.isOwnerSet = isOwnerSet
            self.performedBy = performedBy
            self.isAllTimePR = isAllTimePR
        }
    }

    public struct PerformerRef: Equatable {
        public var personID: UUID
        public var isMe: Bool
        public var name: String

        public init(personID: UUID, isMe: Bool, name: String) {
            self.personID = personID
            self.isMe = isMe
            self.name = name
        }
    }

    /// Pre-computed context for one exercise card, scoped to one performer.
    public struct PerformerContext: Equatable {
        public var performerID: UUID?
        public var label: String
        public var isMe: Bool
        public var lastTimeSets: [SetDisplay] = []
        public var pr: Double?
        public var prRuleName: String = ""
        public var priorSamples: [SetSample] = []
        public var firstWorkingWeightKg: Double?
        public var repLadders: [[Int]] = []
        /// This performer's working-set rep ladders across ALL movements, oldest
        /// first — how they train in general when they have never done THIS lift
        /// (field test 2026-08-19 #3).
        public var generalRepLadders: [[Int]] = []

        public init(performerID: UUID?, label: String, isMe: Bool,
                    lastTimeSets: [SetDisplay], pr: Double?, prRuleName: String,
                    priorSamples: [SetSample], firstWorkingWeightKg: Double?,
                    repLadders: [[Int]], generalRepLadders: [[Int]] = []) {
            self.performerID = performerID
            self.label = label
            self.isMe = isMe
            self.lastTimeSets = lastTimeSets
            self.pr = pr
            self.prRuleName = prRuleName
            self.priorSamples = priorSamples
            self.firstWorkingWeightKg = firstWorkingWeightKg
            self.repLadders = repLadders
            self.generalRepLadders = generalRepLadders
        }
    }

    public struct PendingSetDisplay: Equatable, Identifiable {
        public var id: String { "\(performerID?.uuidString ?? "owner")-\(setIndex)" }
        public var performerID: UUID?
        public var performerName: String
        public var setIndex: Int
        public var targetReps: Int
        public var targetWeightKg: Double?

        public init(performerID: UUID?, performerName: String, setIndex: Int,
                    targetReps: Int, targetWeightKg: Double?) {
            self.performerID = performerID
            self.performerName = performerName
            self.setIndex = setIndex
            self.targetReps = targetReps
            self.targetWeightKg = targetWeightKg
        }
    }

    /// Everything needed to render one exercise card.
    public struct ExerciseContext: Equatable {
        public var exerciseID: UUID
        public var name: String
        public var sets: [SetDisplay] = []
        public var pendingCount: Int = 0
        public var pendingReps: [Int] = []
        public var pendingSets: [PendingSetDisplay] = []
        public var performerContexts: [PerformerContext] = []
        public var hasPartners: Bool { performerContexts.count > 1 }
        /// The performer whose pending row leads the card — the alternation
        /// answer for "who goes next" on this exercise. `nil` is the owner; with
        /// no pending rows the field is `nil` and callers fall back to rotation.
        public var nextPerformerID: UUID? { pendingSets.first?.performerID }

        public init(exerciseID: UUID, name: String, sets: [SetDisplay],
                    pendingCount: Int, pendingReps: [Int],
                    performerContexts: [PerformerContext],
                    pendingSets: [PendingSetDisplay] = []) {
            self.exerciseID = exerciseID
            self.name = name
            self.sets = sets
            self.pendingCount = pendingCount
            self.pendingReps = pendingReps
            self.performerContexts = performerContexts
            self.pendingSets = pendingSets
        }
    }

    /// The full precomputed render state.
    public struct State {
        public var contexts: [ExerciseContext]
        public var prSetIDs: Set<UUID>

        public init(contexts: [ExerciseContext], prSetIDs: Set<UUID>) {
            self.contexts = contexts
            self.prSetIDs = prSetIDs
        }

        /// Check whether a candidate set would be a PR for the owner against
        /// cached prior samples — no SwiftData scan.
        public func wouldBePR(weightKg: Double, reps: Int, isWarmup: Bool,
                              rule: PRRule, formula: OneRepMaxFormula,
                              for exerciseID: UUID) -> Bool {
            guard let ctx = contexts.first(where: { $0.exerciseID == exerciseID }),
                  let owner = ctx.performerContexts.first(where: { $0.isMe }) else {
                return false
            }
            let candidate = SetSample(weight: weightKg, reps: reps, isWarmup: isWarmup)
            return PRCalculator.isNewPR(candidate: candidate, previous: owner.priorSamples,
                                        rule: rule, formula: formula)
        }

        /// The next outstanding set for one performer on one exercise. The set
        /// editor uses it so switching "Who did this set?" re-targets the reps and
        /// weight to that person (field test 2026-08-19 #2).
        public func nextPendingSet(forExerciseID id: UUID,
                                   performerID: UUID?) -> PendingSetDisplay? {
            contexts.first { $0.exerciseID == id }?
                .pendingSets.first { $0.performerID == performerID }
        }

        /// One performer's precomputed history for an exercise, ready for
        /// `PerformerSetPlanner` — no SwiftData scan on the editor's hot path.
        public func performerHistory(forExerciseID id: UUID,
                                     performerID: UUID?) -> PerformerSetPlanner.History {
            guard let performer = contexts.first(where: { $0.exerciseID == id })?
                .performerContexts.first(where: { $0.performerID == performerID })
            else { return .empty }
            return PerformerSetPlanner.History(
                repLadders: performer.repLadders,
                generalRepLadders: performer.generalRepLadders,
                firstWorkingWeightKg: performer.firstWorkingWeightKg)
        }
    }

    /// Cache-invalidation key. Keystroke state (weight/reps/RPE fields) is
    /// structurally absent — only structural session changes drive a rebuild.
    public struct Signature: Equatable {
        public var sessionID: UUID
        public var setCount: Int
        public var latestSetUpdate: Date?
        public var exerciseIDs: [UUID]
        public var plannedNames: [String]
        public var rosterIDs: [String]
        public var prRule: PRRule
        public var formula: OneRepMaxFormula

        public init(sessionID: UUID, setCount: Int, latestSetUpdate: Date?,
                    exerciseIDs: [UUID], plannedNames: [String],
                    rosterIDs: [String], prRule: PRRule, formula: OneRepMaxFormula) {
            self.sessionID = sessionID
            self.setCount = setCount
            self.latestSetUpdate = latestSetUpdate
            self.exerciseIDs = exerciseIDs
            self.plannedNames = plannedNames
            self.rosterIDs = rosterIDs
            self.prRule = prRule
            self.formula = formula
        }
    }

    /// Compute the signature from a session + settings. Keystroke state is not
    /// an input — keystrokes never produce a new signature.
    public static func signature(session: WorkoutSession,
                                 prRule: PRRule,
                                 formula: OneRepMaxFormula) -> Signature {
        let sets = session.orderedSets
        let latest = sets.map(\.updatedAt).max()
        let exerciseIDs = session.exercisesInOrder.map(\.id)
        return Signature(
            sessionID: session.id,
            setCount: sets.count,
            latestSetUpdate: latest,
            exerciseIDs: exerciseIDs,
            plannedNames: session.plannedExerciseNames,
            rosterIDs: session.activePartnerIDs,
            prRule: prRule,
            formula: formula
        )
    }

    /// Build the full render state. Pure — no side effects.
    ///
    /// `recentSessions` is the user's recent training history (any order); it is
    /// used ONLY to derive each performer's habitual rep pattern across movements
    /// they have trained, so a partner who has never done *this* lift still gets
    /// their own usual reps instead of the generic 5 (field test 2026-08-19 #3).
    /// Passing an empty array reproduces the previous behaviour exactly.
    public static func build(session: WorkoutSession,
                             prRule: PRRule,
                             formula: OneRepMaxFormula,
                             allPeople: [Person],
                             recentSessions: [WorkoutSession] = []) -> State {
        var contexts: [ExerciseContext] = []
        var prSetIDs = Set<UUID>()

        let hasPartners = SessionRoster.hasPartners(activePartnerIDs: session.activePartnerIDs, allPeople: allPeople)
        let activePartners = SessionRoster.scopedPartners(activePartnerIDs: session.activePartnerIDs, allPeople: allPeople)
        let generalLadders = generalRepLadders(recentSessions: recentSessions, excluding: session)

        for exercise in session.exercisesInOrder {
            let exerciseSets = session.orderedSets.filter { $0.exercise?.id == exercise.id }
            let allExerciseSets = (exercise.sets ?? [])
            let excludingCurrent = allExerciseSets.filter { $0.session?.id != session.id }

            // Build completed set displays + detect all-time PRs
            var displayedSets: [SetDisplay] = []
            for set in exerciseSets {
                let isPR = !set.isWarmup && set.isOwnerSet && set.reps > 0 && set.effectiveLoadKg > 0 &&
                    PRCalculator.isNewPR(
                        candidate: SetSample.from(set),
                        previous: excludingCurrent.filter { $0.isOwnerSet }.map { SetSample.from($0) },
                        rule: prRule, formula: formula
                    )
                if isPR { prSetIDs.insert(set.id) }

                displayedSets.append(SetDisplay(
                    setID: set.id,
                    weight: set.weight,
                    reps: set.reps,
                    rpe: set.rpe,
                    isWarmup: set.isWarmup,
                    usesBodyweight: set.usesBodyweight,
                    isOwnerSet: set.isOwnerSet,
                    performedBy: performerRef(set.performedBy),
                    isAllTimePR: isPR
                ))
            }

            // Build performer contexts
            var performerContexts: [PerformerContext] = []

            performerContexts.append(performerContext(
                performerID: nil, label: "Me", isMe: true,
                exercise: exercise, excluding: session, prRule: prRule, formula: formula,
                generalRepLadders: generalLadders[performerKey(nil)] ?? []))

            if hasPartners {
                for partner in activePartners {
                    // An explicitly added partner is part of set planning even
                    // before they have history for this movement. Their editor
                    // can then resolve a general rep pattern (or its fallback)
                    // independently from the owner's coach ladder.
                    performerContexts.append(performerContext(
                        performerID: partner.id, label: partner.name, isMe: false,
                        exercise: exercise, excluding: session, prRule: prRule, formula: formula,
                        generalRepLadders: generalLadders[performerKey(partner.id)] ?? []))
                }
            }

            let ownerPlan = plannedSets(forPerformerID: nil, exerciseName: exercise.name, session: session)
            var pendingByPerformer: [[PendingSetDisplay]] = []
            for performer in performerContexts {
                // A per-performer plan entered in the editor is that performer's
                // own target and OUTRANKS their history (field test 2026-08-19
                // #1). Absent an entry this resolves to the owner's prescription,
                // exactly as it did before the field existed.
                let explicitPlan = session.explicitPlannedSets(forPerformerID: performer.performerID,
                                                               exerciseName: exercise.name)
                let plan = explicitPlan ?? ownerPlan
                let performerSets = exerciseSets
                    .filter { setPerformedBy($0, performerID: performer.performerID) && !$0.isWarmup }
                    .sorted { $0.order < $1.order }
                let history = PerformerSetPlanner.History(
                    repsLoggedThisSession: performerSets.map(\.reps),
                    repLadders: performer.repLadders,
                    generalRepLadders: performer.generalRepLadders,
                    firstWorkingWeightKg: performer.firstWorkingWeightKg)
                var rows: [PendingSetDisplay] = []
                if performerSets.count < plan.count {
                    for index in performerSets.count..<plan.count {
                        let resolved = PerformerSetPlanner.resolve(
                            setIndex: index,
                            performerPlan: explicitPlan,
                            ownerPlan: ownerPlan,
                            ownerLadder: nil,
                            isOwner: performer.isMe,
                            history: history)
                        rows.append(PendingSetDisplay(
                            performerID: performer.performerID, performerName: performer.label,
                            setIndex: index, targetReps: resolved.reps,
                            targetWeightKg: resolved.weightKg))
                    }
                }
                pendingByPerformer.append(rows)
            }
            // Partners train the same movement together, so the remaining work
            // ALTERNATES: my set 1, their set 1, my set 2, … — never two
            // consecutive rows from one performer while the other still owes
            // rows (field test 2026-08-19 #1; decision D2).
            let pendingSets = SetAlternation.spread(pendingByPerformer)
            let ownerPending = pendingSets.filter { $0.performerID == nil }
            let pendingReps = ownerPending.map(\.targetReps)

            contexts.append(ExerciseContext(
                exerciseID: exercise.id,
                name: exercise.name,
                sets: displayedSets,
                pendingCount: pendingSets.count,
                pendingReps: pendingReps,
                performerContexts: performerContexts,
                pendingSets: pendingSets
            ))
        }

        return State(contexts: contexts, prSetIDs: prSetIDs)
    }

    // MARK: - Private helpers

    private static func performerContext(performerID: UUID?, label: String, isMe: Bool,
                                          exercise: Exercise, excluding session: WorkoutSession?,
                                          prRule: PRRule, formula: OneRepMaxFormula,
                                          generalRepLadders: [[Int]] = []) -> PerformerContext {
        let last: [SetEntry]
        let pr: Double?
        let samples: [SetSample]
        let firstWeight: Double?
        let ladders: [[Int]]

        if isMe {
            last = WorkoutRepository.lastTimeSets(for: exercise, excluding: session)
            pr = WorkoutRepository.currentPR(for: exercise, rule: prRule, formula: formula, excluding: session)
            samples = (exercise.sets ?? [])
                .filter { $0.isOwnerSet && $0.session?.id != session?.id }
                .map { SetSample.from($0) }
            firstWeight = WorkoutRepository.firstWorkingSetWeight(for: exercise, performedBy: nil, excluding: session)
            ladders = WorkoutRepository.repLadderHistory(for: exercise, performedBy: nil, excluding: session)
        } else {
            let person = (exercise.sets ?? []).compactMap(\.performedBy).first { $0.id == performerID }
            // A partner with no sets on this movement has no "last time" — the
            // repository's nil-person query means the owner, so guard on the
            // person actually existing (field test 2026-08-20 issue 2, D5).
            last = person.map { WorkoutRepository.lastTimeSets(for: exercise, performedBy: $0, excluding: session) } ?? []
            // Partner PR not computed — only owner sets count
            pr = nil
            samples = (exercise.sets ?? [])
                .filter { $0.performedBy?.id == performerID && $0.session?.id != session?.id }
                .map { SetSample.from($0) }
            firstWeight = WorkoutRepository.firstWorkingSetWeight(for: exercise, performedBy: person, excluding: session)
            ladders = WorkoutRepository.repLadderHistory(for: exercise, performedBy: person, excluding: session)
        }

        return PerformerContext(
            performerID: performerID,
            label: label,
            isMe: isMe,
            lastTimeSets: last.map { setDisplay($0) },
            pr: pr,
            prRuleName: prRule.displayName,
            priorSamples: samples,
            firstWorkingWeightKg: firstWeight,
            repLadders: ladders,
            generalRepLadders: generalRepLadders
        )
    }

    /// Stable dictionary key for a performer; the owner is `performedBy == nil`.
    public static func performerKey(_ id: UUID?) -> String { id?.uuidString ?? "owner" }

    /// The prescription stored for one performer, or nil when they have none.
    /// Unlike `WorkoutSession.plannedPrescriptions(forPerformerID:)` this never
    /// substitutes the owner's plan, so callers can tell "planned" from "absent".
    private static func plannedSets(forPerformerID id: UUID?, exerciseName: String,
                                    session: WorkoutSession) -> [PlannedSetPrescription] {
        session.explicitPlannedSets(forPerformerID: id, exerciseName: exerciseName)
            ?? session.plannedRepLadder.map {
                PlannedSetPrescription(targetReps: $0,
                                       targetWeightKg: session.prescribedLoadKg > 0 ? session.prescribedLoadKg : nil)
            }
    }

    /// Each performer's working-set rep ladders across every movement in the
    /// supplied history, oldest first, keyed by `performerKey`. Capped to the most
    /// recent sessions so a long history costs a bounded walk.
    public static func generalRepLadders(recentSessions: [WorkoutSession],
                                         excluding session: WorkoutSession) -> [String: [[Int]]] {
        guard !recentSessions.isEmpty else { return [:] }
        var result: [String: [[Int]]] = [:]
        let window = recentSessions
            .filter { $0.id != session.id && $0.deletedAt == nil }
            .sorted { $0.date < $1.date }
            .suffix(generalHistoryWindow)
        for past in window {
            var byPerformer: [String: [Int]] = [:]
            for set in past.orderedSets where !set.isWarmup && set.reps > 0 {
                let key = set.isOwnerSet ? performerKey(nil) : performerKey(set.performedBy?.id)
                byPerformer[key, default: []].append(set.reps)
            }
            for (key, reps) in byPerformer where !reps.isEmpty {
                result[key, default: []].append(reps)
            }
        }
        return result
    }

    /// Enough sessions to establish a pattern without walking a long history on
    /// every structural change. Matches `WorkoutPlanPartnerHistory`.
    private static let generalHistoryWindow = 20

    private static func plannedSetCount(session: WorkoutSession) -> Int {
        session.plannedRepLadder.isEmpty ? 0 : session.plannedRepLadder.count
    }

    private static func setPerformedBy(_ set: SetEntry, performerID: UUID?) -> Bool {
        guard let performerID else { return set.isOwnerSet }
        return set.performedBy?.id == performerID
    }

    private static func performerRef(_ p: Person?) -> PerformerRef? {
        guard let p else { return nil }
        return PerformerRef(personID: p.id, isMe: p.isMe, name: p.name)
    }

    private static func setDisplay(_ set: SetEntry) -> SetDisplay {
        SetDisplay(
            setID: set.id,
            weight: set.weight,
            reps: set.reps,
            rpe: set.rpe,
            isWarmup: set.isWarmup,
            usesBodyweight: set.usesBodyweight,
            isOwnerSet: set.isOwnerSet,
            performedBy: performerRef(set.performedBy),
            isAllTimePR: false
        )
    }
}
