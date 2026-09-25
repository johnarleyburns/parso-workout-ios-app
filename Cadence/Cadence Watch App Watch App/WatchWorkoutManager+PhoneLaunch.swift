import Foundation
import HealthKit
import WatchKit

// MARK: - Workouts the iPhone opens on the Watch
//
// When Cladiron isn't running on the Watch, the phone opens it with
// `HKHealthStore.startWatchApp(with:)`. watchOS launches or wakes the app and
// hands the workout configuration to `CadenceWatchAppDelegate.handle(_:)`,
// possibly with the screen off. The workout starts at once, because a running
// workout is what keeps the app alive in the background. Before launching, the
// phone queues its `start_workout` command with `transferUserInfo`; that is
// delivered, in order, once WatchConnectivity activates here and attaches the
// phone's request ID to this workout (`adoptPhoneLaunchedWorkout`).

extension WatchWorkoutManager {
    /// How long a phone-launched workout waits for the phone's command before
    /// ending itself, so a launch the phone never follows up (the phone app
    /// quit, or the attempt was cancelled) doesn't leave a workout running.
    static let phoneLaunchAdoptionTimeout: Duration = .seconds(90)

    func startPhoneLaunchedWorkout(configuration: HKWorkoutConfiguration) {
        setDisplayActive(WKApplication.shared().applicationState == .active)
        activateWCSessionForBackgroundLaunch()
        // Already running: the phone's command arrived first (it owns the
        // workout), or the user is in a Watch workout, which the command will
        // be told about.
        guard !isActive, !isMonitoring else { return }
        guard startWorkout(type: Self.rawType(for: configuration.activityType)) else { return }
        let launchedAt = Date()
        phoneLaunchPendingSince = launchedAt
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.phoneLaunchAdoptionTimeout)
            self?.endUnclaimedPhoneLaunch(startedAt: launchedAt)
        }
    }

    /// Attaches the phone's request to the workout its launch started.
    /// Returns false when there is no such workout to adopt.
    func adoptPhoneLaunchedWorkout(requestID: UUID, type: String) -> Bool {
        guard phoneLaunchPendingSince != nil, phoneRequestID == nil, isActive else { return false }
        phoneLaunchPendingSince = nil
        phoneRequestID = requestID.uuidString
        workoutType = type
        persistWorkoutMetadata(type: type, monitoring: false)
        // Sends a reading that is already in, and arms the heartbeat, which
        // reads the builder even while the screen is off.
        sendHeartRateToPhoneSoon()
        return true
    }

    /// watchOS relaunched the app in the background to recover a workout that
    /// was running when it quit or crashed. Reattach before any UI exists so
    /// a phone-started workout keeps streaming.
    func recoverAfterBackgroundRelaunch() {
        setDisplayActive(WKApplication.shared().applicationState == .active)
        activateWCSessionForBackgroundLaunch()
        recoverActiveWorkoutIfNeeded()
    }

    /// A launch can skip the UI (screen off), and with it the root view's own
    /// activation; queued commands and the relay need the session.
    private func activateWCSessionForBackgroundLaunch() {
        guard !uiTestMode, wcSession?.activationState != .activated else { return }
        activateWCSession()
    }

    private func endUnclaimedPhoneLaunch(startedAt: Date) {
        guard phoneLaunchPendingSince == startedAt, phoneRequestID == nil, isActive else { return }
        stopWorkout(save: false)
    }
}
