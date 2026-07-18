import Foundation
import CadenceCore

/// Per-render snapshot of everything `SessionView` needs to render exercise
/// cards without scanning SwiftData on every keystroke. An `Equatable Signature`
/// gates rebuilds; identical signatures skip the work.
public enum SessionRenderModel {

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

    /// Everything needed to render one exercise card.
    public struct ExerciseContext: Equatable {
        public var exerciseID: UUID
        public var name: String
        public var sets: [SetDisplay] = []
        public var pendingCount: Int = 0
        public var pendingReps: [Int] = []
        public var performerContexts: [PerformerContext] = []
        public var hasPartners: Bool { performerContexts.count > 1 }

        public init(exerciseID: UUID, name: String, sets: [SetDisplay],
                    pendingCount: Int, pendingReps: [Int],
                    performerContexts: [PerformerContext]) {
            self.exerciseID = exerciseID
            self.name = name
            self.sets = sets
            self.pendingCount = pendingCount
            self.pendingReps = pendingReps
            self.performerContexts = performerContexts
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
                    if !pc.lastTimeSets.isEmpty {
                        performerContexts.append(pc)
                    }
                }
            } else {
                performerContexts.append(performerContext(
                    performerID: nil, label: "Me", isMe: true,
                    exercise: exercise, excluding: session, prRule: prRule, formula: formula))
            }

            let pending = max(0, plannedSetCount(session: session) - exerciseSets.count)
            let pendingReps = (0..<pending).map { offset in
                let setIndex = exerciseSets.count + offset
                let currentReps = exerciseSets.sorted { $0.order < $1.order }.map(\.reps)
                let owner = performerContexts.first { $0.isMe }
                let prior = owner?.repLadders ?? []
                let lastLogged = exerciseSets.last?.reps
                return SessionViewModel.plannedReps(
                    ladder: SessionViewModel.effectiveLadder(session: session),
                    setIndex: setIndex,
                    currentSessionReps: currentReps,
                    priorSessionLadders: prior,
                    lastLoggedReps: lastLogged)
            }

            contexts.append(ExerciseContext(
                exerciseID: exercise.id,
                name: exercise.name,
                sets: displayedSets,
                pendingCount: pending,
                pendingReps: pendingReps,
                performerContexts: performerContexts
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
            last = WorkoutRepository.lastTimeSets(for: exercise, performedBy: nil, excluding: session)
                .filter { $0.performedBy?.id == performerID }
            // Partner PR not computed — only owner sets count
            pr = nil
            samples = (exercise.sets ?? [])
                .filter { $0.performedBy?.id == performerID && $0.session?.id != session?.id }
                .map { SetSample.from($0) }
            firstWeight = nil
            ladders = []
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
