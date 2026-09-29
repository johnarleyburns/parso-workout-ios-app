#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

/// The ActivityKit contract is compiled into both the iPhone app and the
/// widget extension. Keeping it in the shared module is required: duplicate
/// declarations in the two targets produce different module-qualified types,
/// so ActivityKit can create an activity that the extension cannot render.
public struct WorkoutLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var status: String
        public var elapsedSeconds: Int
        public var isPaused: Bool
        public var restEndsAt: Date?
        public var nextExercise: String?

        public init(status: String, elapsedSeconds: Int, isPaused: Bool = false,
                    restEndsAt: Date? = nil, nextExercise: String? = nil) {
            self.status = status
            self.elapsedSeconds = elapsedSeconds
            self.isPaused = isPaused
            self.restEndsAt = restEndsAt
            self.nextExercise = nextExercise
        }
    }

    public var workoutTitle: String

    public init(workoutTitle: String) {
        self.workoutTitle = workoutTitle
    }
}
#endif
