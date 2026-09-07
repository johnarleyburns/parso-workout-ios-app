import Foundation
import HealthKit
import CadenceFeatures

extension WatchWorkoutManager {
    /// Reattaches to a HealthKit workout that survived a Watch app crash or
    /// process relaunch. HealthKit owns the workout session, so reopening the
    /// app must recover that session instead of starting a second one.
    func recoverActiveWorkoutIfNeeded() {
        guard !uiTestMode, !isActive, !isMonitoring else { return }
        guard UserDefaults.standard.bool(forKey: PersistedWorkoutKey.active) else { return }
        store.recoverActiveWorkoutSession { [weak self] recovered, _ in
            guard let recovered else {
                Task { @MainActor [weak self] in
                    self?.clearPersistedWorkoutMetadata()
                }
                return
            }
            Task { @MainActor [weak self] in
                self?.attachRecoveredWorkout(recovered)
            }
        }
    }

    func beginSession(activity: HKWorkoutActivityType, spec: WorkoutConfigurationSpec? = nil) {
        let config = HKWorkoutConfiguration()
        config.activityType = activity; config.locationType = .indoor
        if let spec {
            switch spec.location {
            case .indoor: break
            case .outdoor: config.locationType = .outdoor; isOutdoorSession = true
            case .pool(let lapLength):
                config.swimmingLocationType = .pool; isSwimSession = true
                if #available(watchOS 10.0, *) { config.lapLength = HKQuantity(unit: .meter(), doubleValue: lapLength) }
            case .openWater: config.swimmingLocationType = .openWater; isSwimSession = true
            }
        }
        sessionStart = Date(); autoPauseDetector.reset(); manualLapCount = 0; autoLapCount = 0
        guard !uiTestMode else { return }
        do {
            let s = try HKWorkoutSession(healthStore: store, configuration: config)
            session = s
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            b.delegate = self; builder = b; s.delegate = self
            s.startActivity(with: Date())
            b.beginCollection(withStart: Date(), completion: { _, _ in })
            if hrSource == .bluetooth { startBLE() }
            if isSwimSession { enableWaterLock() }
        } catch {
            isActive = false
            isMonitoring = false
            session = nil
            builder = nil
            sessionStart = nil
            clearPersistedWorkoutMetadata()
        }
    }

    private func attachRecoveredWorkout(_ recovered: HKWorkoutSession) {
        guard recovered.state != .ended, recovered.state != .stopped else {
            clearPersistedWorkoutMetadata()
            return
        }

        let defaults = UserDefaults.standard
        let monitoring = defaults.bool(forKey: PersistedWorkoutKey.monitoring)
        let recoveredType = defaults.string(forKey: PersistedWorkoutKey.type)
            ?? Self.rawType(for: recovered.workoutConfiguration.activityType)

        session = recovered
        recovered.delegate = self
        let recoveredBuilder = recovered.associatedWorkoutBuilder()
        recoveredBuilder.dataSource = HKLiveWorkoutDataSource(
            healthStore: store,
            workoutConfiguration: recovered.workoutConfiguration)
        recoveredBuilder.delegate = self
        builder = recoveredBuilder

        workoutType = recoveredType
        phoneRequestID = defaults.string(forKey: PersistedWorkoutKey.phoneRequestID)
        isMonitoring = monitoring
        isActive = !monitoring
        heartRateEnabled = true
        gpsEnabled = recovered.workoutConfiguration.locationType == .outdoor
        sessionStart = recovered.startDate ?? Date()
        if recovered.state == .running {
            startHeartRatePolling()
        }
    }

    func persistWorkoutMetadata(type: String, monitoring: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: PersistedWorkoutKey.active)
        defaults.set(type, forKey: PersistedWorkoutKey.type)
        defaults.set(monitoring, forKey: PersistedWorkoutKey.monitoring)
        if let phoneRequestID {
            defaults.set(phoneRequestID, forKey: PersistedWorkoutKey.phoneRequestID)
        } else {
            defaults.removeObject(forKey: PersistedWorkoutKey.phoneRequestID)
        }
    }

    func clearPersistedWorkoutMetadata() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: PersistedWorkoutKey.active)
        defaults.removeObject(forKey: PersistedWorkoutKey.type)
        defaults.removeObject(forKey: PersistedWorkoutKey.monitoring)
        defaults.removeObject(forKey: PersistedWorkoutKey.phoneRequestID)
    }

    static func rawType(for activity: HKWorkoutActivityType) -> String {
        switch activity {
        case .boxing: return "boxing"
        case .highIntensityIntervalTraining: return "hiit"
        case .running: return "run"
        case .cycling: return "cycle"
        case .swimming: return "swim"
        case .walking: return "walk"
        case .rowing: return "rowing"
        case .other: return "other"
        default: return "strength"
        }
    }
}
