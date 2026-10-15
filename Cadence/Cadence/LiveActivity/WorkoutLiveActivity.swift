@preconcurrency import ActivityKit
import Foundation
import CadenceFeatures
import OSLog

/// Best-effort lock-screen status for an active iPhone workout. The embedded
/// Watch app deliberately keeps using HKWorkoutSession, whose system workout
/// UI is the native watch equivalent of this surface.
@MainActor
final class WorkoutLiveActivityCoordinator {
    static let shared = WorkoutLiveActivityCoordinator()
    private let logger = Logger(subsystem: "guru.parso.ios-workout-app", category: "WorkoutLiveActivity")
    private var activity: Activity<WorkoutLiveActivityAttributes>?

    func start(title: String, restEndsAt: Date? = nil, nextExercise: String? = nil,
               nextSetSummary: String? = nil, nextSetToken: String? = nil) {
        // Launch recovery and the active-state observer can both reconcile the
        // same workout. Do not tear down a valid activity and recreate it in
        // the same launch window.
        guard activity == nil else { return }
        endAllStale()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = WorkoutLiveActivityAttributes(workoutTitle: title)
        let state = WorkoutLiveActivityAttributes.ContentState(status: String(localized: "Active"), elapsedSeconds: 0,
                                                               restEndsAt: restEndsAt,
                                                               nextExercise: nextExercise,
                                                               nextSetSummary: nextSetSummary,
                                                               nextSetToken: nextSetToken)
        do {
            activity = try Activity.request(attributes: attributes,
                                            content: ActivityContent(state: state, staleDate: LiveActivityReconcilePolicy.staleDate(from: Date())))
        } catch {
            // A missing entitlement, disabled Live Activities setting, or a
            // rejected ActivityKit request must be diagnosable instead of
            // silently leaving the user with an apparently blank activity.
            logger.error("Live Activity request failed: \(String(describing: error), privacy: .public)")
        }
    }

    func update(elapsedSeconds: Int, status: String, isPaused: Bool,
                restEndsAt: Date? = nil, nextExercise: String? = nil,
                nextSetSummary: String? = nil, nextSetToken: String? = nil) {
        guard let activity else { return }
        let state = WorkoutLiveActivityAttributes.ContentState(status: status,
                                                               elapsedSeconds: elapsedSeconds,
                                                               isPaused: isPaused,
                                                               restEndsAt: restEndsAt,
                                                               nextExercise: nextExercise,
                                                               nextSetSummary: nextSetSummary,
                                                               nextSetToken: nextSetToken)
        Task { @MainActor [activity] in
            await activity.update(ActivityContent(state: state, staleDate: LiveActivityReconcilePolicy.staleDate(from: Date())))
        }
    }

    /// Ends every owned activity, not just the one this process adopted: an
    /// activity from a prior launch would otherwise keep its counter running.
    func end() {
        endAllStale()
    }

    /// Ends all owned activities when no strength workout is active.
    func reconcile(workoutIsActive: Bool, hasStrengthSession: Bool) {
        let action = LiveActivityReconcilePolicy.action(
            workoutIsActive: workoutIsActive, hasStrengthSession: hasStrengthSession,
            ownedActivityCount: Activity<WorkoutLiveActivityAttributes>.activities.count)
        if action == .endAll { endAllStale() }
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
