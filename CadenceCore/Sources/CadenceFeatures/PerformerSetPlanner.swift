import Foundation
import CadenceCore

/// Resolves what ONE performer's next set should be, for one exercise, at one
/// set index — the single source of truth shared by the live session's pending
/// rows (`SessionRenderModel`) and the set editor's pre-fill (`SessionView`).
///
/// Field test 2026-08-19:
///  * **#1** — a per-performer plan entered in the plan editor was discarded the
///    moment the performer had any history for the movement, because the render
///    model derived reps from history *first* and only fell back to the plan.
///    The explicit plan is now the **top** precedence for both reps and weight;
///    history only fills what the plan does not say.
///  * **#3** — a partner who has never trained *this* movement fell all the way
///    through to the literal `5`, ignoring the hundreds of 20-rep sets they had
///    logged on every other movement. `habitualReps` supplies their modal working
///    rep count before that last resort is reached.
///
/// Pure by construction: callers gather history from `WorkoutRepository` and hand
/// it in as values, so this stays `swift test`-able.
public enum PerformerSetPlanner {

    public enum WeightBasis: Equatable, Sendable {
        case explicitPlan
        case ownerPlan
        case exactHistory
        case estimatedHistory
        case priorHistory
        case none
    }

    /// The resolved target for one set. `weightKg` nil means "no opinion" — the
    /// editor leaves the field empty rather than inventing a load.
    public struct Resolved: Equatable, Sendable {
        public var reps: Int
        public var weightKg: Double?
        public var weightBasis: WeightBasis

        public init(reps: Int, weightKg: Double?, weightBasis: WeightBasis = .none) {
            self.reps = reps
            self.weightKg = weightKg
            self.weightBasis = weightBasis
        }
    }

    /// One performer's logged history, scoped to the exercise being resolved
    /// except for `generalRepLadders`, which spans every movement they have done.
    public struct History: Equatable, Sendable {
        /// Working-set reps this performer has already logged in THIS session
        /// for THIS exercise, in logged order.
        public var repsLoggedThisSession: [Int]
        /// Prior sessions' working-set rep ladders for THIS exercise, oldest first.
        public var repLadders: [[Int]]
        /// Prior sessions' working-set rep ladders across ALL exercises, oldest
        /// first. The basis for `habitualReps`.
        public var generalRepLadders: [[Int]]
        /// The performer's own first working weight for this exercise (kg).
        public var firstWorkingWeightKg: Double?
        /// Prior working sets for this performer and movement, oldest first.
        /// Used to make a transparent, rep-aware load suggestion.
        public var weightSamples: [SetSample]

        public init(repsLoggedThisSession: [Int] = [],
                    repLadders: [[Int]] = [],
                    generalRepLadders: [[Int]] = [],
                    firstWorkingWeightKg: Double? = nil,
                    weightSamples: [SetSample] = []) {
            self.repsLoggedThisSession = repsLoggedThisSession
            self.repLadders = repLadders
            self.generalRepLadders = generalRepLadders
            self.firstWorkingWeightKg = firstWorkingWeightKg
            self.weightSamples = weightSamples
        }

        public static let empty = History()

        /// True when this performer has trained THIS movement before, or already
        /// has a set in the current session for it.
        public var hasMovementHistory: Bool {
            !repsLoggedThisSession.isEmpty || repLadders.contains { !$0.isEmpty }
        }
    }

    /// The performer's habitual working-set rep count across every movement they
    /// have logged: the modal value, ties broken by the most recent occurrence.
    ///
    /// A partner who does 20 reps on everything reads as 20 on a brand-new lift
    /// (field test 2026-08-19 #3) instead of the generic 5.
    public static func habitualReps(generalRepLadders: [[Int]]) -> Int? {
        let reps = generalRepLadders.flatMap { $0 }.filter { $0 > 0 }
        guard !reps.isEmpty else { return nil }
        var counts: [Int: Int] = [:]
        var lastSeen: [Int: Int] = [:]
        for (index, value) in reps.enumerated() {
            counts[value, default: 0] += 1
            lastSeen[value] = index
        }
        return counts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return (lastSeen[lhs.key] ?? 0) < (lastSeen[rhs.key] ?? 0)
        }?.key
    }

    /// The last resort when a performer has told us nothing at all.
    public static let defaultReps = 5

    /// Resolve the target for `setIndex`.
    ///
    /// Reps, in order:
    ///  1. the performer's own **explicit plan** for this set (field test #1);
    ///  2. the owner's coach ladder — owner only, never a partner's;
    ///  3. this movement's own history (`RepPattern`, then the most recent ladder);
    ///  4. what they last logged for this movement;
    ///  5. their **habitual** reps across every movement (field test #3);
    ///  6. the owner's planned reps at this index;
    ///  7. `defaultReps`.
    ///
    /// Weight, in order: the explicit plan's weight → their own first working
    /// weight for this movement → (owner only) the owner plan's weight. A partner
    /// NEVER inherits the owner's load (decision **D13**).
    public static func resolve(setIndex: Int,
                               performerPlan: [PlannedSetPrescription]?,
                               ownerPlan: [PlannedSetPrescription],
                               ownerLadder: [Int]?,
                               isOwner: Bool,
                               history: History,
                               formula: OneRepMaxFormula = .epley) -> Resolved {
        let planned = performerPlan.flatMap { setIndex < $0.count ? $0[setIndex] : nil }
        let ownerPlanned = setIndex < ownerPlan.count ? ownerPlan[setIndex] : nil

        let weight: Double?
        let weightBasis: WeightBasis
        if let plannedWeight = planned?.targetWeightKg, plannedWeight > 0 {
            weight = plannedWeight
            weightBasis = .explicitPlan
        } else if let suggestion = WeightSuggestion.suggest(
            targetReps: reps(setIndex: setIndex, planned: planned,
                             ownerPlanned: ownerPlanned,
                             ownerLadder: isOwner ? ownerLadder : nil,
                             history: history),
            history: history.weightSamples,
            formula: formula) {
            weight = suggestion.weightKg
            weightBasis = suggestion.basis == .exactRepMatch ? .exactHistory : .estimatedHistory
        } else if let prior = history.firstWorkingWeightKg, prior > 0 {
            weight = prior
            weightBasis = .priorHistory
        } else if isOwner, let ownerWeight = ownerPlanned?.targetWeightKg, ownerWeight > 0 {
            weight = ownerWeight
            weightBasis = .ownerPlan
        } else {
            weight = nil
            weightBasis = .none
        }

        return Resolved(reps: reps(setIndex: setIndex,
                                   planned: planned,
                                   ownerPlanned: ownerPlanned,
                                   ownerLadder: isOwner ? ownerLadder : nil,
                                   history: history),
                        weightKg: (weight ?? 0) > 0 ? weight : nil,
                        weightBasis: weightBasis)
    }

    private static func reps(setIndex: Int,
                             planned: PlannedSetPrescription?,
                             ownerPlanned: PlannedSetPrescription?,
                             ownerLadder: [Int]?,
                             history: History) -> Int {
        if let value = planned?.targetReps, value > 0 { return value }
        if let ladder = ownerLadder, setIndex < ladder.count, ladder[setIndex] > 0 {
            return ladder[setIndex]
        }
        let ladders = history.repLadders.filter { !$0.isEmpty }
        if setIndex > 0,
           let guess = RepPattern.guess(setIndex: setIndex,
                                        currentSessionReps: history.repsLoggedThisSession,
                                        priorSessionLadders: ladders),
           guess > 0 {
            return guess
        }
        if let recent = ladders.last, setIndex < recent.count, recent[setIndex] > 0 {
            return recent[setIndex]
        }
        if let last = history.repsLoggedThisSession.last, last > 0 { return last }
        if let last = ladders.last?.last, last > 0 { return last }
        if let habit = habitualReps(generalRepLadders: history.generalRepLadders) { return habit }
        if let value = ownerPlanned?.targetReps, value > 0 { return value }
        return defaultReps
    }
}
