@preconcurrency import ActivityKit
import Foundation

struct WorkoutLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: String
        var elapsedSeconds: Int
        var isPaused: Bool

        init(status: String, elapsedSeconds: Int, isPaused: Bool = false) {
            self.status = status
            self.elapsedSeconds = elapsedSeconds
            self.isPaused = isPaused
        }
    }

    var workoutTitle: String
}

/// Best-effort lock-screen status for an active iPhone workout. The embedded
/// Watch app deliberately keeps using HKWorkoutSession, whose system workout
/// UI is the native watch equivalent of this surface.
@MainActor
final class WorkoutLiveActivityCoordinator {
    static let shared = WorkoutLiveActivityCoordinator()
    private var activity: Activity<WorkoutLiveActivityAttributes>?

    func start(title: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = WorkoutLiveActivityAttributes(workoutTitle: title)
        let state = WorkoutLiveActivityAttributes.ContentState(status: "Active", elapsedSeconds: 0)
        activity = try? Activity.request(attributes: attributes,
                                         content: ActivityContent(state: state, staleDate: nil))
    }

    func update(elapsedSeconds: Int, status: String, isPaused: Bool) {
        guard let activity else { return }
        let state = WorkoutLiveActivityAttributes.ContentState(status: status,
                                                               elapsedSeconds: elapsedSeconds,
                                                               isPaused: isPaused)
        Task { @MainActor [activity] in
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        Task { @MainActor [activity] in
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
