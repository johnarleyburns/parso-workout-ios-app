import Foundation
import CadenceCore

/// Per-render snapshot of everything `SessionView` needs to render exercise
/// cards without scanning SwiftData on every keystroke. An `Equatable Signature`
/// gates rebuilds; identical signatures skip the work.
public enum SessionRenderModel {

    /// Compact, collapsed-card copy. It intentionally contains no editing
    /// affordances; the disclosure control is the only collapsed interaction.
    public static func compactSummary(context: ExerciseContext,
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

        public init(performerID: UUID?, label: String, isMe: Bool,
                    lastTimeSets: [SetDisplay], pr: Double?, prRuleName: String,
                    priorSamples: [SetSample], firstWorkingWeightKg: Double?,
                    repLadders: [[Int]]) {
            self.performerID = performerID
            self.label = label
            self.isMe = isMe
            self.lastTimeSets = lastTimeSets
            self.pr = pr
            self.prRuleName = prRuleName
            self.priorSamples = priorSamples
            self.firstWorkingWeightKg = firstWorkingWeightKg
            self.repLadders = repLadders
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
    public static func build(session: WorkoutSession,
                             prRule: PRRule,
                             formula: OneRepMaxFormula,
                             allPeople: [Person]) -> State {
        var contexts: [ExerciseContext] = []
        var prSetIDs = Set<UUID>()

        let hasPartners = SessionRoster.hasPartners(activePartnerIDs: session.activePartnerIDs, allPeople: allPeople)
        let activePartners = SessionRoster.scopedPartners(activePartnerIDs: session.activePartnerIDs, allPeople: allPeople)

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

            if hasPartners {
                performerContexts.append(performerContext(
                    performerID: nil, label: "Me", isMe: true,
                    exercise: exercise, excluding: session, prRule: prRule, formula: formula))

                for partner in activePartners {
                    let pc = performerContext(
                        performerID: partner.id, label: partner.name, isMe: false,
                        exercise: exercise, excluding: session, prRule: prRule, formula: formula)
                    // An explicitly added partner is part of set planning even
                    // before they have history for this movement. Their editor
                    // can then resolve a general rep pattern (or its fallback)
                    // independently from the owner's coach ladder.
                    performerContexts.append(pc)
                }
            } else {
                performerContexts.append(performerContext(
                    performerID: nil, label: "Me", isMe: true,
                    exercise: exercise, excluding: session, prRule: prRule, formula: formula))
            }

            var pendingSets: [PendingSetDisplay] = []
            for performer in performerContexts {
                // A partner's plan, when the editor stored one, is that
                // partner's own starting target (field test 2026-08-18 #4,
                // decision D11). Absent an entry this resolves to the owner's
                // prescription, exactly as it did before the field existed.
                let prescription = session.plannedPrescriptions(forPerformerID: performer.performerID).first {
                    $0.exerciseName.caseInsensitiveCompare(exercise.name) == .orderedSame
                }
                let plannedSets = prescription?.sets ?? session.plannedRepLadder.map {
                    PlannedSetPrescription(targetReps: $0, targetWeightKg: session.prescribedLoadKg > 0 ? session.prescribedLoadKg : nil)
                }
                let performerSets = exerciseSets.filter { setPerformedBy($0, performerID: performer.performerID) && !$0.isWarmup }
                let currentReps = performerSets.sorted { $0.order < $1.order }.map(\.reps)
                let ladders = performer.repLadders.isEmpty
                    ? generalRepLadderHistory(exercise: exercise, performerID: performer.performerID, excluding: session)
                    : performer.repLadders
                if performerSets.count < plannedSets.count {
                    for index in performerSets.count..<plannedSets.count {
                    let target = plannedSets[index]
                    let hasPerformerHistory = !currentReps.isEmpty || !ladders.isEmpty
                    // The planned target is the LAST resort, not the magic 5 that
                    // `plannedReps` falls back to: with a stored per-performer
                    // plan the first set must honour that plan (field test
                    // 2026-08-18 #4). Later sets still follow the performer's own
                    // rep pattern.
                    let reps = hasPerformerHistory
                        ? SessionViewModel.plannedReps(
                            ladder: nil, setIndex: index, currentSessionReps: currentReps,
                            priorSessionLadders: ladders,
                            lastLoggedReps: performerSets.last?.reps ?? target.targetReps)
                        : target.targetReps
                        pendingSets.append(PendingSetDisplay(
                            performerID: performer.performerID, performerName: performer.label,
                            setIndex: index, targetReps: reps,
                            targetWeightKg: performer.firstWorkingWeightKg ?? target.targetWeightKg))
                    }
                }
            }
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
                                          prRule: PRRule, formula: OneRepMaxFormula) -> PerformerContext {
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
            last = WorkoutRepository.lastTimeSets(for: exercise, performedBy: person, excluding: session)
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
            repLadders: ladders
        )
    }

    private static func plannedSetCount(session: WorkoutSession) -> Int {
        session.plannedRepLadder.isEmpty ? 0 : session.plannedRepLadder.count
    }

    private static func generalRepLadderHistory(exercise: Exercise, performerID: UUID?, excluding session: WorkoutSession) -> [[Int]] {
        let sets = (exercise.sets ?? []).filter {
            $0.session?.id != session.id && !$0.isWarmup && setPerformedBy($0, performerID: performerID)
        }
        let grouped = Dictionary(grouping: sets) { $0.session?.id ?? UUID() }
        return grouped.values.sorted { ($0.first?.session?.date ?? .distantPast) < ($1.first?.session?.date ?? .distantPast) }
            .map { $0.sorted { $0.order < $1.order }.map(\.reps) }
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
