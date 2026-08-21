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
        endAllStale()
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

    /// Ends every Live Activity this app owns. Called on launch and at the top
    /// of every `start` so an activity orphaned by a kill/background can never
    /// keep a stale timer on the lock screen (field-test batch 2026-08-20
    /// issue 5, 5B). `Activity.activities` returns only our own type and is
    /// harmless when empty.
    func endAllStale() {
        for activity in Activity<WorkoutLiveActivityAttributes>.activities {
            Task { @MainActor in await activity.end(nil, dismissalPolicy: .immediate) }
        }
        activity = nil
    }
}
