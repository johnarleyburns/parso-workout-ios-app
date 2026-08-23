import Foundation
import HealthKit

// MARK: - HealthKit / WatchKit session delegates
//
// HealthKit and WatchKit deliver these callbacks on their OWN queues, never on
// the main actor. `WatchWorkoutManager` is `@MainActor`, so an
// `extension … : @preconcurrency HKWorkoutSessionDelegate` compiles but leaves
// the witnesses main-actor-isolated, and Swift 6 inserts a dynamic isolation
// check at each entry point. HealthKit calls `didChangeTo` the instant a session
// starts, off the main thread — the check then traps and the app dies.
//
// That is what broke Live HR, the phone's watch-HR request, and resuming a
// strength workout (which starts a workout session too) after the Swift 6
// migration; only the Bluetooth path, which never opens an `HKWorkoutSession`,
// still worked. Every witness below is therefore `nonisolated` and hops onto the
// main actor explicitly — the same shape the phone's `WCSession` delegate
// already uses (`bca32c9`).
//
// Rule for this file: a witness may touch ONLY its parameters; every piece of
// `WatchWorkoutManager` state is read and written inside the hop.

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {
        Task { @MainActor [weak self] in self?.handleSessionStateChange(toState) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.handleSessionFailure() }
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var sample = CollectedSample()

        let hrType = HKQuantityType(.heartRate)
        if collectedTypes.contains(hrType),
           let stats = workoutBuilder.statistics(for: hrType),
           let quantity = stats.mostRecentQuantity() {
            sample.bpm = quantity.doubleValue(for: HKUnit(from: "count/min"))
        }

        var distanceIDs: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
        if #available(watchOS 11.0, *) { distanceIDs.append(.distanceRowing) }
        for id in distanceIDs {
            let type = HKQuantityType(id)
            if collectedTypes.contains(type),
               let stats = workoutBuilder.statistics(for: type),
               let quantity = stats.sumQuantity() {
                sample.distanceMeters = quantity.doubleValue(for: .meter())
            }
        }

        Task { @MainActor [weak self] in self?.apply(sample) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        guard let type = workoutBuilder.workoutEvents.last?.type, type == .lap || type == .segment else { return }
        Task { @MainActor [weak self] in self?.applyLapEvent() }
    }
}
