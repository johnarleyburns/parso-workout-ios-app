import Foundation

/// The single pure source of truth for "how long is the next rest?".
/// Generated plans, previews, the phone timer, session edits, resume and the
/// Watch (via the serialized prescriptions) all call this; nothing else may
/// do rest arithmetic.
///
/// Rules (deterministic):
/// - Warmup sets: no timer (nil).
/// - Non-final set of an exercise: set rest, else the item's between-set
///   default, else `fallbackSeconds` (the user's ordinary set rest).
/// - Final set of an exercise: the explicit transition rest, else (legacy,
///   absent value) the ordinary between-set rest for that set — so absent
///   transition never changes saved set rest.
/// - Final set of an exercise followed by a superset partner: nil (go
///   straight to the partner).
/// - Final set of the final exercise: nil (workout over; cooldown/mobility
///   items carry no strength rest).
public enum TransitionRestResolver {
    public struct Boundary: Equatable, Sendable {
        public var isLastSetOfExercise: Bool
        public var isLastExercise: Bool
        public var nextSharesSuperset: Bool
        public init(isLastSetOfExercise: Bool, isLastExercise: Bool = false,
                    nextSharesSuperset: Bool = false) {
            self.isLastSetOfExercise = isLastSetOfExercise
            self.isLastExercise = isLastExercise
            self.nextSharesSuperset = nextSharesSuperset
        }
    }

    public static func restSeconds(setRest: Int?, isWarmup: Bool,
                                   defaultRest: Int?, transitionRest: Int?,
                                   boundary: Boundary,
                                   fallbackSeconds: Int) -> Int? {
        if isWarmup { return nil }
        let between = setRest ?? defaultRest ?? fallbackSeconds
        guard boundary.isLastSetOfExercise else { return between }
        if boundary.isLastExercise || boundary.nextSharesSuperset { return nil }
        return transitionRest ?? between
    }

    /// Rest after the `completedSetCount`-th set (1-based) of `exerciseName`
    /// in an ordered list of prescriptions. Unknown exercise/ad-hoc logging
    /// returns `fallbackSeconds` so ordinary behaviour is unchanged.
    public static func restAfterSet(prescriptions: [PlannedExercisePrescription],
                                    exerciseName: String,
                                    completedSetCount: Int,
                                    isWarmup: Bool,
                                    fallbackSeconds: Int) -> Int? {
        if isWarmup { return nil }
        guard let idx = prescriptions.firstIndex(where: {
            $0.exerciseName.caseInsensitiveCompare(exerciseName) == .orderedSame
        }) else { return fallbackSeconds }
        let item = prescriptions[idx]
        let working = item.sets.filter { !$0.isWarmup }
        guard completedSetCount >= 1, completedSetCount <= working.count else {
            // Beyond the plan (extra set): ordinary set rest.
            return item.defaultRestSeconds ?? fallbackSeconds
        }
        let set = working[completedSetCount - 1]
        let next = prescriptions.indices.contains(idx + 1) ? prescriptions[idx + 1] : nil
        let shares = item.supersetGroup != nil && next?.supersetGroup == item.supersetGroup
        return restSeconds(
            setRest: set.restSeconds, isWarmup: false,
            defaultRest: item.defaultRestSeconds,
            transitionRest: item.transitionRestSeconds,
            boundary: Boundary(isLastSetOfExercise: completedSetCount == working.count,
                               isLastExercise: next == nil,
                               nextSharesSuperset: shares),
            fallbackSeconds: fallbackSeconds)
    }

    /// Edit-safe: recompute rests only for sets not yet completed.
    public static func upcomingRests(prescriptions: [PlannedExercisePrescription],
                                     completedCountByExercise: [String: Int],
                                     fallbackSeconds: Int) -> [String: [Int?]] {
        var out: [String: [Int?]] = [:]
        for item in prescriptions {
            let working = item.sets.filter { !$0.isWarmup }.count
            let done = completedCountByExercise[item.exerciseName] ?? 0
            guard done < working else { out[item.exerciseName] = []; continue }
            out[item.exerciseName] = ((done + 1)...working).map {
                restAfterSet(prescriptions: prescriptions, exerciseName: item.exerciseName,
                             completedSetCount: $0, isWarmup: false,
                             fallbackSeconds: fallbackSeconds)
            }
        }
        return out
    }
}
