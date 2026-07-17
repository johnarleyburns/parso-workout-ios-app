import Foundation
import HealthKit
import WatchConnectivity
import WatchKit
import CadenceCore

/// Event-driven workout session controller for the Cladiron Watch App.
///
/// Replaces the old 1s Timer polling with proper `HKLiveWorkoutBuilder`
/// data-collection callbacks. Supports both Apple Watch optical HR and direct
/// BLE chest strap (via `WatchHeartRateBLE`). Persists the user's preferred
/// `HRSource` so it survives restarts.
///
/// WCSession receives `start_workout`/`stop_workout` commands from the phone
/// (legacy FR-8) and also sends commands when the user starts a workout
/// directly on the watch (Phases 2+).
@Observable
final class WatchWorkoutManager: NSObject {

    // MARK: Published state

    /// Current heart rate from the active source, or nil if no data yet.
    private(set) var currentBPM: Double?

    /// Whether a workout session is currently active.
    private(set) var isActive: Bool = false

    /// The `CardioType` raw value for the current workout, if any.
    private(set) var workoutType: String?

    /// User's preferred HR source (persisted in `UserDefaults`).
    var hrSource: HRSource {
        get { HRSource(rawValue: hrSourceRaw) ?? .appleWatch }
        set { hrSourceRaw = newValue.rawValue }
    }

    /// Whether the optical HR sensor is authorized by the user.
    private(set) var hrAuthorized: Bool = false

    /// Connection state of the BLE chest strap (nil when not scanning).
    private(set) var bleState: BLEConnectionState? = nil
    private(set) var bleBattery: Int? = nil

    private var hrSourceRaw: String {
        get { UserDefaults.standard.string(forKey: "watch.hrSource") ?? HRSource.appleWatch.rawValue }
        set { UserDefaults.standard.set(newValue, forKey: "watch.hrSource") }
    }

    // MARK: Private

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var extendedSession: WKExtendedRuntimeSession?
    private var ble: WatchHeartRateBLE?

    private var wcSession: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    // MARK: WCSession activation

    func activateWCSession() {
        guard let session = wcSession else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: HealthKit authorization

    func requestHRAuthorization() async -> Bool {
        let hrType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        let types: Set<HKObjectType> = [HKObjectType.workoutType(), hrType]
        do {
            try await store.requestAuthorization(toShare: [.workoutType()], read: types)
            let status = store.authorizationStatus(for: hrType)
            hrAuthorized = (status == .sharingAuthorized)
            return hrAuthorized
        } catch {
            return false
        }
    }

    // MARK: Workout control

    /// Starts a workout session. Called either from a phone command or locally
    /// when the user taps a workout row in the launcher.
    func startWorkout(type rawType: String, cardioType: CardioType? = nil) {
        guard !isActive else { return }

        workoutType = rawType
        isActive = true

        let activity = Self.activityType(for: rawType)

        Task {
            let authorized = await requestHRAuthorization()
            guard authorized else {
                isActive = false
                return
            }
            await MainActor.run { beginSession(activity: activity) }
        }
    }

    func stopWorkout() {
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in self?.builder = nil }
        session?.end()
        session = nil
        extendedSession?.invalidate()
        extendedSession = nil
        ble?.disconnect()
        ble = nil
        currentBPM = nil
        isActive = false
        workoutType = nil
        bleState = nil
    }

    // MARK: HR source switching

    func switchToSource(_ source: HRSource) {
        hrSource = source
        guard isActive else { return }

        switch source {
        case .appleWatch:
            ble?.disconnect(); ble = nil; bleState = nil
        case .bluetooth:
            startBLE()
        }
    }

    func startBLE() {
        ble = WatchHeartRateBLE { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                switch event {
                case .connected(let battery):
                    self.bleState = .connected
                    self.bleBattery = battery
                case .disconnected:
                    self.bleState = .disconnected
                    self.bleBattery = nil
                case .bpm(let value):
                    self.currentBPM = value
                    self.relayBPM(value)
                case .scanning:
                    self.bleState = .scanning
                case .batteryUpdated(let pct):
                    self.bleBattery = pct
                }
            }
        }
        bleState = .scanning
        ble?.start()
    }

    func stopBLE() {
        ble?.disconnect()
        ble = nil
        bleState = nil
    }

    // MARK: Helpers

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

            // Start extended runtime session for background / Always-On
            extendedSession = WKExtendedRuntimeSession()
            extendedSession?.delegate = self
            extendedSession?.start()

            // If the user prefers BLE, start scanning now
            if hrSource == .bluetooth { startBLE() }
        } catch {
            isActive = false
            session = nil
            builder = nil
        }
    }

    private func relayBPM(_ bpm: Double) {
        guard let session = wcSession, session.isReachable else { return }
        session.sendMessage(["bpm": bpm, "active": true], replyHandler: nil, errorHandler: nil)
    }

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
        default: return .functionalStrengthTraining
        }
    }
}

// MARK: - BLE connection state

extension WatchWorkoutManager {
    enum BLEConnectionState {
        case scanning
        case connected
        case disconnected
    }
}

// MARK: - WCSessionDelegate

extension WatchWorkoutManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleMessage(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handleMessage(message)
        replyHandler(["ack": true])
    }

    private func handleMessage(_ message: [String: Any]) {
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
                        from fromState: HKWorkoutSessionState, date: Date) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        stopWorkout()
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate (event-driven HR)

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard hrSource == .appleWatch, isActive else { return }

        let hrType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hrType) else { return }

        if let stats = workoutBuilder.statistics(for: hrType),
           let qty = stats.mostRecentQuantity() {
            let bpm = qty.doubleValue(for: HKUnit(from: "count/min"))
            Task { @MainActor in
                self.currentBPM = bpm
                self.relayBPM(bpm)
            }
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension WatchWorkoutManager: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {}
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}
}
