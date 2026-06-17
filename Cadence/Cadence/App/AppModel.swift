import Foundation
import SwiftUI
import Observation
import WatchConnectivity
import CadenceCore

/// Central dependency container injected through the environment. Chooses real
/// platform services or deterministic fakes based on launch arguments so the
/// app is fully UI-testable on the simulator (which has no Health/BLE/GPS data).
///
/// Also acts as the phone-side WCSession delegate for FR-8: receives live HR
/// from the Apple Watch and feeds it into the same `HeartRateMonitor` pipeline
/// as the BLE chest strap.
///
/// WCSession activation is deferred to `activateWCSession()`, called from
/// `CadenceApp.task{}` so it never blocks app launch.
@Observable
final class AppModel: NSObject {
    let health: HealthDataProviding
    let hrm: HeartRateMonitor
    let location: LocationTracker
    let isUITestMode: Bool

    /// Whether the Apple Watch is actively streaming HR (FR-8).
    private(set) var watchActive: Bool = false
    /// When set, the watch was told to start but never confirmed.
    private(set) var watchError: String?
    private var watchTimeout: Timer?

    /// Cached once at launch — avoids hitting `WCSession.default.isWatchAppInstalled`
    /// (a synchronous IPC call) from SwiftUI body evaluation.
    private(set) var watchAppInstalled: Bool = false

    /// Last time we ingested HealthKit workouts (FR-2.1), persisted across runs.
    var lastHealthSync: Date? {
        get { (UserDefaults.standard.object(forKey: SettingsKey.lastHealthSync) as? Double).map { Date(timeIntervalSince1970: $0) } }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970, forKey: SettingsKey.lastHealthSync) }
    }

    override init() {
        let args = ProcessInfo.processInfo.arguments
        let uiTest = args.contains("-uiTest")
        self.isUITestMode = uiTest

        if uiTest {
            let fake = FakeHealthProvider()
            fake.authStatus = .authorized
            if let idx = args.firstIndex(of: "-todaySteps"), idx + 1 < args.count, let n = Int(args[idx + 1]) {
                fake.seededTodaySteps = n
            }
            self.health = fake
        } else {
            self.health = HealthKitProvider()
        }

        self.hrm = HeartRateMonitor(simulated: uiTest)
        self.location = LocationTracker(simulated: uiTest)

        super.init()
    }

    // MARK: Watch HR relay (FR-8)

    /// Is the Apple Watch available to stream HR? Uses cached value to avoid
    /// synchronous IPC calls from SwiftUI body evaluation.
    var watchAvailable: Bool {
        !isUITestMode && watchAppInstalled
    }

    /// Activates the WCSession and caches `isWatchAppInstalled`. Called once from
    /// `CadenceApp.task{}` so it doesn't block launch (FR-8 reliability fix).
    func activateWCSession() {
        guard !isUITestMode, WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        // Cache synchronously after activation — the value is valid once
        // the session is active.
        watchAppInstalled = session.isWatchAppInstalled
    }

    /// Tells the Apple Watch to start an `HKWorkoutSession` for the given
    /// exercise type and begin streaming live heart rate.
    func startWatchWorkout(type: CardioType) {
        startWatchWorkout(rawType: type.rawValue)
    }

    /// Starts a Watch workout for strength (maps to `.functionalStrengthTraining`).
    func startWatchStrength() {
        startWatchWorkout(rawType: "strength")
    }

    /// Tells the Apple Watch to start an `HKWorkoutSession` for the given
    /// raw type string and begin streaming live heart rate.
    func startWatchWorkout(rawType: String) {
        guard watchAvailable, let session = wcSession else { return }
        watchError = nil
        watchTimeout?.invalidate()
        session.sendMessage(["command": "start_workout", "type": rawType],
                            replyHandler: { [weak self] _ in
            // Watch acknowledged — BPM should arrive soon.
        }, errorHandler: { [weak self] _ in
            DispatchQueue.main.async {
                self?.watchActive = false
                self?.watchError = "Watch unreachable"
                self?.watchTimeout?.invalidate()
            }
        })
        watchActive = true
        // Timeout: if no BPM arrives within 15 s, reset and show error.
        watchTimeout = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard self?.watchActive == true else { return }
                self?.watchActive = false
                self?.watchError = "No response from Watch"
                self?.watchTimeout?.invalidate()
            }
        }
    }

    /// Tells the Apple Watch to end the `HKWorkoutSession` and stop streaming.
    func stopWatchWorkout() {
        watchTimeout?.invalidate(); watchTimeout = nil
        guard watchAvailable, let session = wcSession else { return }
        session.sendMessage(["command": "stop_workout"],
                            replyHandler: nil, errorHandler: nil)
        watchActive = false
        watchError = nil
    }

    private var wcSession: WCSession? {
        guard WCSession.isSupported() else { return nil }
        let s = WCSession.default
        return s.activationState == .activated ? s : nil
    }
}

// MARK: - WCSessionDelegate (FR-8)

extension AppModel: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            watchAppInstalled = session.isWatchAppInstalled
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let bpm = message["bpm"] as? Double else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.watchTimeout?.invalidate(); self.watchTimeout = nil
            self.watchError = nil
            self.hrm.injectExternalBPM(bpm)
        }
    }
}
