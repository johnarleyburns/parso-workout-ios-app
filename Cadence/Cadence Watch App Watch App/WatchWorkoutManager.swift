import Foundation
import SwiftUI
import HealthKit
import WatchConnectivity
import CadenceCore

/// Drives the Apple Watch optical heart-rate sensor during a workout and
/// relays live BPM to the iPhone via WCSession (FR-8).
///
/// The iPhone **cannot** read the Watch's live HR directly — HealthKit only
/// exposes periodic, stale samples.  A watchOS `HKWorkoutSession` unlocks
/// continuous sensor reading; this class starts one on command from the phone,
/// reads HR every second via the live builder, and sends `["bpm": <value>]`
/// messages to the phone.
@Observable
final class WatchWorkoutManager: NSObject {

    // MARK: Published state

    private(set) var currentBPM: Double?
    private(set) var isActive: Bool = false
    private(set) var workoutType: String? // CardioType rawValue sent from phone

    // MARK: Private

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var hrTimer: Timer?

    private var wcSession: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    // MARK: WCSession activation

    func activateWCSession() {
        guard let session = wcSession else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: Workout control

    func startWorkout(type rawType: String) {
        guard !isActive else { return }

        workoutType = rawType
        isActive = true

        let activity = Self.activityType(for: rawType)
        requestAuthorization { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.isActive = false
                return
            }
            self.beginSession(activity: activity)
        }
    }

    func stopWorkout() {
        hrTimer?.invalidate(); hrTimer = nil
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.builder = nil
        }
        session?.end()
        session = nil
        currentBPM = nil
        isActive = false
        workoutType = nil
    }

    // MARK: Helpers

    private func requestAuthorization(completion: @escaping (Bool) -> Void) {
        let types: Set<HKObjectType> = [HKObjectType.workoutType(),
                                        HKObjectType.quantityType(forIdentifier: .heartRate)!]
        store.requestAuthorization(toShare: [.workoutType()], read: types) { _, _ in
            completion(true) // proceed regardless; session will notify of errors
        }
    }

    private func beginSession(activity: HKWorkoutActivityType) {
        let config = HKWorkoutConfiguration()
        config.activityType = activity
        config.locationType = .indoor

        do {
            let s = try HKWorkoutSession(healthStore: store, configuration: config)
            self.session = s
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            b.delegate = self
            self.builder = b

            s.delegate = self
            s.startActivity(with: Date())
            b.beginCollection(withStart: Date(), completion: { _, _ in })
        } catch {
            isActive = false
            session = nil
            builder = nil
        }
    }

    private func startHRPolling() {
        hrTimer?.invalidate()
        hrTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let builder = self.builder, self.isActive else { return }
            let hrType = HKQuantityType(.heartRate)
            if let stats = builder.statistics(for: hrType),
               let qty = stats.mostRecentQuantity() {
                let bpm = qty.doubleValue(for: HKUnit(from: "count/min"))
                self.currentBPM = bpm
                self.sendBPM(bpm)
            }
        }
    }

    private func sendBPM(_ bpm: Double) {
        guard let session = wcSession, session.isReachable else { return }
        session.sendMessage(["bpm": bpm, "active": true], replyHandler: nil, errorHandler: nil)
    }

    /// Maps a `CardioType` raw value (or empty string for strength) to an
    /// `HKWorkoutActivityType`.
    static func activityType(for rawType: String) -> HKWorkoutActivityType {
        switch rawType {
        case "boxing": return .boxing
        case "hiit": return .highIntensityIntervalTraining
        case "run": return .running
        case "cycle": return .cycling
        case "swim": return .swimming
        case "walk": return .walking
        case "rowing": return .rowing
        case "other": return .other
        default: return .functionalStrengthTraining // strength / unknown
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchWorkoutManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["command"] as? String == "start_workout",
           let type = message["type"] as? String {
            startWorkout(type: type)
        } else if message["command"] as? String == "stop_workout" {
            stopWorkout()
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .running { startHRPolling() }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        stopWorkout()
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {}
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
