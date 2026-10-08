import Foundation
import HealthKit
import WatchKit
import CadenceFeatures

extension WatchWorkoutManager {
    static func swimSpec(from config: HKWorkoutConfiguration) -> WorkoutConfigurationSpec? {
        guard config.activityType == .swimming else { return nil }
        let location: WorkoutConfigurationSpec.Location = config.swimmingLocationType == .openWater
            ? .openWater : .pool(lapLength: config.lapLength?.doubleValue(for: .meter()) ?? 25)
        return WorkoutConfigurationSpec(kind: .swim, location: location)
    }

    /// Retry on foreground activation if the running callback arrived in the
    /// background. Do not re-lock every wrist raise after the user unlocks.
    func enablePendingSwimWaterLock() {
        let device = WKInterfaceDevice.current()
        guard !uiTestMode, WatchSwimSetup.shouldWaterLock(
            pending: swimWaterLockPending, running: session?.state == .running,
            foreground: WKApplication.shared().applicationState == .active,
            supported: device.waterResistanceRating == .wr50) else { return }
        swimWaterLockPending = false
        if !device.isWaterLockEnabled { device.enableWaterLock() }
    }

    func enableWaterLock() {
        let device = WKInterfaceDevice.current()
        guard !uiTestMode, session?.state == .running || session?.state == .paused,
              WKApplication.shared().applicationState == .active,
              device.waterResistanceRating == .wr50 else { return }
        swimWaterLockPending = false
        device.enableWaterLock()
    }

    func applyLapEvent(builderID: ObjectIdentifier) {
        guard builder.map(ObjectIdentifier.init) == builderID, !isSwimSession else { return }
        autoLapCount += 1
    }

    func handleSessionStateChange(_ state: HKWorkoutSessionState) {
        if state == .running {
            startHeartRatePolling()
            sendHeartRateToPhoneSoon()
            enablePendingSwimWaterLock()
        } else if (state == .ended || state == .stopped), isActive || isMonitoring {
            stopWorkout(save: false)
        }
    }
}
