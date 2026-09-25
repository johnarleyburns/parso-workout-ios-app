import Foundation
import HealthKit
import CadenceFeatures

/// HealthKit authorization and the first-screen Heart Rate Access boundary.
///
/// The boundary used to hang off a sticky UserDefaults flag, so it disappeared
/// for good after one tap on any build, even when HealthKit had never been
/// asked. It now follows HealthKit's own request status
/// (`WatchHealthAuthorizationGate`): it shows first on every launch until the
/// system sheet has been answered, and never after.
extension WatchWorkoutManager {
    var needsInitialHealthAuthorization: Bool {
        !uiTestMode && healthAuthorizationGateActive
    }

    /// The types every Watch workout reads and writes. One definition keeps
    /// the status check and the request asking about exactly the same set.
    static var healthShareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.quantityType(forIdentifier: .distanceSwimming)!,
        ]
        if #available(watchOS 11.0, *) {
            if let rowing = HKObjectType.quantityType(forIdentifier: .distanceRowing) {
                types.insert(rowing)
            }
        }
        return types
    }

    static var healthReadTypes: Set<HKObjectType> {
        [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.quantityType(forIdentifier: .distanceSwimming)!,
        ]
    }

    /// Asks HealthKit whether the permission sheet still needs answering and
    /// updates the boundary and the launcher's "Health access needed" row.
    /// Called at launch and after every authorization request.
    func refreshHealthAuthorizationState() async {
        guard !uiTestMode else { return }
        refreshShareAuthorization()
        let status: WatchHealthAuthorizationGate.RequestStatus
        do {
            switch try await store.statusForAuthorizationRequest(toShare: Self.healthShareTypes,
                                                                 read: Self.healthReadTypes) {
            case .shouldRequest: status = .shouldRequest
            case .unnecessary: status = .unnecessary
            default: status = .unknown
            }
        } catch {
            status = .unknown
        }
        WatchHealthAuthorizationGate.record(status)
        healthAuthorizationGateActive = WatchHealthAuthorizationGate.gateActive(
            current: healthAuthorizationGateActive,
            status: status,
            dismissedThisLaunch: healthPromptDismissedThisLaunch,
            flowStarted: healthAuthorizationFlowStarted)
    }

    /// Write access is the one part HealthKit reports. Refreshing it at launch
    /// stops the launcher from claiming "Health access needed" on every launch
    /// after access was granted.
    func refreshShareAuthorization() {
        workoutShareAuthorized = store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
        let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate)!
        hrAuthorized = store.authorizationStatus(for: heartRate) != .notDetermined
    }

    /// Skips the boundary for this launch only. It comes back next launch while
    /// HealthKit still has never been asked.
    func continueWithoutHealthAuthorization() {
        healthPromptDismissedThisLaunch = true
        healthAuthorizationGateActive = false
    }

    /// Keep the first-launch permission surface visible until the user
    /// explicitly chooses to continue after the system sheet returns.
    func finishInitialHealthAuthorization() {
        healthAuthorizationGateActive = false
        UserDefaults.standard.set(true, forKey: WatchHealthAuthorizationGate.resolvedKey)
    }

    @discardableResult
    func requestWorkoutAuthorization() async -> Bool {
        guard !uiTestMode else {
            workoutShareAuthorized = true
            hrAuthorized = true
            return true
        }
        healthAuthorizationFlowStarted = true
        do {
            try await store.requestAuthorization(toShare: Self.healthShareTypes, read: Self.healthReadTypes)
            await refreshHealthAuthorizationState()
            return workoutShareAuthorized
        } catch {
            return false
        }
    }
}
