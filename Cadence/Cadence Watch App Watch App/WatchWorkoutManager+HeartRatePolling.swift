import Foundation
import HealthKit

extension WatchWorkoutManager {
    /// Apple Fitness auto-detection can briefly interrupt WatchConnectivity
    /// reachability while Cladiron still has a live HealthKit sample stream.
    /// Retry the latest value so the phone recovers without a second workout
    /// start.
    func startHeartRateRelayPolling() {
        relayTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive || self.isMonitoring,
                      let bpm = self.currentBPM else { return }
                self.relayBPM(bpm)
            }
        }
        relayTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// HealthKit's builder delegate may batch callbacks for tens of seconds.
    /// Polling the live builder's latest statistics restores the one-second UI
    /// and phone relay cadence used by the original, responsive implementation.
    func startHeartRatePolling() {
        hrPollTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollHeartRate() }
        }
        hrPollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    #if DEBUG
    var isHeartRatePollingForTesting: Bool { hrPollTimer?.isValid == true }
    #endif

    fileprivate func pollHeartRate() {
        guard isActive || isMonitoring, let builder else { return }
        let hrType = HKQuantityType(.heartRate)
        guard let bpm = builder.statistics(for: hrType)?.mostRecentQuantity()?
            .doubleValue(for: HKUnit(from: "count/min")) else { return }
        applyPolledHeartRate(bpm)
    }
}
