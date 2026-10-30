import Foundation
import CadenceCore

/// One set of an exercise in the active Watch workout, by exercise name.
public struct WatchSuggestionSet: Equatable, Sendable {
    public var exerciseName: String
    public var isWarmup: Bool

    public init(exerciseName: String, isWarmup: Bool = false) {
        self.exerciseName = exerciseName
        self.isWarmup = isWarmup
    }
}

/// Pure adapter: persisted phone context + the active Watch workout's state ->
/// `SuggestedWorkoutInput` for the shared generator. No UI, no workout writes,
/// and the context is a value that is never mutated.
///
/// Allocation matches the phone's `activeAllocatedVolume()` planned-totals
/// semantics: each non-warmup set credits its exercise's `VolumeCredit` per
/// muscle group (direct 1.0, indirect 0.5, none when not volume-eligible). Credits
/// are resolved only from the snapshot's candidate metadata; an active exercise
/// without metadata adds no allocation (safe omission) but is still excluded by
/// its canonical name key.
public enum WatchSingleExerciseSuggestionAssembler {
    public static func make(context: WatchSingleExerciseSuggestionContext,
                            activeExerciseNames: [String],
                            activeWorkingSets: [WatchSuggestionSet],
                            transientExcludedCandidateIDs: Set<String>) -> SuggestedWorkoutInput? {
        let byName = Dictionary(
            context.baseInput.candidates.map { (ExerciseLibrary.dedupKey($0.name), $0) },
            uniquingKeysWith: { first, _ in first })

        var excluded = transientExcludedCandidateIDs
        for name in activeExerciseNames {
            excluded.insert(ExerciseSuggestionExclusionKey.forName(name))
            if let candidate = byName[ExerciseLibrary.dedupKey(name)] { excluded.insert(candidate.id) }
        }

        var allocated: [String: Double] = [:]
        for set in activeWorkingSets where !set.isWarmup {
            guard let candidate = byName[ExerciseLibrary.dedupKey(set.exerciseName)],
                  let credits = credits(for: candidate) else { continue }
            for (group, credit) in credits where credit > 0 {
                allocated[group.rawValue, default: 0] += credit
            }
        }
        return context.suggestedWorkoutInput(allocated: allocated, excluding: excluded)
    }

    private static func credits(for c: WatchSingleExerciseSuggestionContext.Candidate)
    -> [MuscleGroup: Double]? {
        let primary = MuscleGroup.canonicalize(c.primaryMuscles)
        let secondary = MuscleGroup.canonicalize(c.secondaryMuscles).filter { !primary.contains($0) }
        return VolumeCredit.credits(direct: primary, indirect: secondary, volumeEligible: c.volumeEligible)
    }
}
