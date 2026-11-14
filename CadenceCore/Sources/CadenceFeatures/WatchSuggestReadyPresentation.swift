import Foundation

/// Presentation policy for the Watch Strength → Suggest ready screen. No recommendation logic.
public enum WatchSuggestReadyPresentation {
    public static let startTitle = "Start"
    public static let activeWorkoutExplanation = "Finish or resume your current workout first."
    public static let showsReadyProvenance = false
    public static let showsReadySyncTimestamp = false
    public static let showsAggregateWorkingSetCount = false
    public static let usesGreenProminentStartAction = true

    public static func showsSupplementalDetail(_ detail: String) -> Bool { !detail.isEmpty }
    public static func isStartDisabled(workoutActive: Bool) -> Bool { workoutActive }
    public static func activeWorkoutMessage(workoutActive: Bool) -> String? {
        workoutActive ? activeWorkoutExplanation : nil
    }
}
