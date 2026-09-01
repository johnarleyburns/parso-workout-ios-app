import Foundation

/// The single source of truth for how one working set is credited to muscle
/// groups. `TrainingFacts`, the plan-aware weekly accounting, the coach plan
/// optimizer and the suggested-workout generator all resolve credit through here,
/// so a screen and a nag can never disagree about how much a set counted for.
///
/// The model is free-exercise-db++'s published set-credit convention: a muscle the
/// movement trains **directly** earns 1.0, one trained **indirectly** earns 0.5,
/// and one that only **stabilises** earns 0.0. These are analytical credits for
/// volume accounting, not a claim that fatigue or hypertrophy is linear — the
/// dose-response work behind them is `pellandDoseResponse2026`.
public enum VolumeCredit {

    /// Read from DB++ rather than hard-coded, so an upstream model refresh cannot
    /// silently disagree with our arithmetic.
    public static var direct: Double { TrainingEngineBridge.setCredits.direct }
    public static var indirect: Double { TrainingEngineBridge.setCredits.indirect }
    public static var stabilizer: Double { TrainingEngineBridge.setCredits.stabilizer }

    /// The citation behind the credit model. Rendered wherever the split is stated
    /// on screen (HARD RULE: every science claim cites).
    public static let citationID = "pellandDoseResponse2026"

    /// Credit from raw role lists. Direct wins when a group appears in both, and a
    /// movement that is not volume-eligible credits nothing at all no matter what
    /// its muscle lists say.
    public static func credits(direct directMuscles: [MuscleGroup],
                               indirect indirectMuscles: [MuscleGroup],
                               volumeEligible: Bool) -> [MuscleGroup: Double] {
        guard volumeEligible else { return [:] }
        var result: [MuscleGroup: Double] = [:]
        for group in directMuscles { result[group] = direct }
        for group in indirectMuscles where result[group] == nil { result[group] = indirect }
        return result
    }

    /// Credit from a catalog template.
    public static func credits(for template: ExerciseTemplate) -> [MuscleGroup: Double] {
        credits(direct: template.directMuscles, indirect: template.indirectMuscles,
                volumeEligible: template.volumeEligible)
    }
}

public extension VolumeCredit {
    /// Credit from a stored exercise. Honours `volumeEligible`, and falls back to
    /// primary/secondary when the DB++ role arrays are empty — which is what keeps
    /// custom exercises, and a store that has not been re-seeded, counting.
    static func credits(for exercise: Exercise) -> [MuscleGroup: Double] {
        exercise.volumeCredits
    }
}
