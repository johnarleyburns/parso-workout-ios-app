import Foundation
import HealthKit
import WatchKit

/// Owns the workout manager so the workout the iPhone starts with
/// `HKHealthStore.startWatchApp` (delivered to `handle(_:)`, possibly before
/// any UI exists) reaches the same manager the UI shows. Also tells the
/// manager when the screen turns on and off.
@MainActor
final class CadenceWatchAppDelegate: NSObject, WKApplicationDelegate {
    let watchManager = WatchWorkoutManager(uiTestMode: ProcessInfo.processInfo.arguments.contains("-uiTest"))

    override init() {
        super.init()
        // UI-test-only seam (requires -uiTest): present an active phone-owned workout,
        // then deliver one heart-rate sample after a short delay.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uiTest"), arguments.contains("-uiTestPhoneWorkout") {
            watchManager.isActive = true
            watchManager.phoneRequestID = "ui-test-phone-request"
            let manager = watchManager
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                manager.currentBPM = 72
            }
        }
    }

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        watchManager.startPhoneLaunchedWorkout(configuration: workoutConfiguration)
    }

    func handleActiveWorkoutRecovery() {
        watchManager.recoverAfterBackgroundRelaunch()
    }

    func applicationDidBecomeActive() {
        watchManager.setDisplayActive(true)
    }

    func applicationWillResignActive() {
        watchManager.setDisplayActive(false)
    }
}
