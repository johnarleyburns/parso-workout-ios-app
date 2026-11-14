import Foundation

/// Presentation for one row of the Watch Plan page: the ring shows the completed-set count, the name
/// gets a consistent two-line area, and there is no textual progress detail.
public struct WatchWorkoutExerciseRowPresentation: Equatable, Sendable {
    /// Every row reserves this many lines for the exercise name.
    public static let exerciseNameMaxLines = 2

    public let exerciseName: String
    public let completedSetCount: Int
    public let plannedSetCount: Int
    public let isPlanned: Bool
    public let progress: Double

    public var exerciseNameMaxLines: Int { Self.exerciseNameMaxLines }
    public var showsTextualProgressDetail: Bool { false }

    public init(exerciseName: String, completedSetCount: Int, plannedSetCount: Int?) {
        let done = max(0, completedSetCount)
        let planned = max(0, plannedSetCount ?? 0)
        self.exerciseName = exerciseName
        self.completedSetCount = done
        self.plannedSetCount = planned
        self.isPlanned = planned > 0
        self.progress = planned > 0 ? min(1, Double(done) / Double(planned)) : 0
    }

    /// Full name plus progress, for VoiceOver.
    public var accessibilityLabel: String {
        if isPlanned {
            return "\(exerciseName), \(completedSetCount) of \(plannedSetCount) sets complete"
        }
        return "\(exerciseName), \(completedSetCount) sets logged"
    }
}
