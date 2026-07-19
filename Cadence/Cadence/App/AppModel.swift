import Foundation
import SwiftUI
import Observation
import SwiftData
import WatchConnectivity
import CadenceCore
import CadenceFeatures
#if DEBUG
import CadenceFixtures
#endif

/// Central dependency container injected through the environment. Chooses real
/// platform services or deterministic fakes based on launch arguments so the
/// app is fully UI-testable on the simulator (which has no Health/BLE/GPS data).
///
/// Also contains the phone-side WCSession plumbing for live Apple Watch HR
/// relay. The watch companion app ships embedded in the phone archive (Phase 0).
///
/// WCSession activation is deferred to `activateWCSession()`, called from
/// `CadenceApp.task{}` so it never blocks app launch.
@Observable
final class AppModel: NSObject {
    private static let liveWatchHREnabled = true

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
    private(set) var watchSyncState: WatchSync.Status = .idle
    private(set) var lastWatchSyncAt: Date? = UserDefaults.standard.object(forKey: "settings.lastWatchSyncAt") as? Date
    private(set) var lastWatchSyncError: String?

    /// Last time we ingested HealthKit workouts (FR-2.1), persisted across runs.
    var lastHealthSync: Date? {
        get { (UserDefaults.standard.object(forKey: SettingsKey.lastHealthSync) as? Double).map { Date(timeIntervalSince1970: $0) } }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970, forKey: SettingsKey.lastHealthSync) }
    }

    override init() {
        let args = ProcessInfo.processInfo.arguments
        let uiTest = args.contains("-uiTest")
        self.isUITestMode = uiTest

        #if DEBUG
        if uiTest {
            let fake = FakeHealthProvider()
            fake.authStatus = .authorized
            if let idx = args.firstIndex(of: "-todaySteps"), idx + 1 < args.count, let n = Int(args[idx + 1]) {
                fake.seededTodaySteps = n
            }
            if args.contains("-noHealthWorkouts") {
                fake.pendingWorkouts = []
            }
            self.health = fake
        } else {
            self.health = HealthKitProvider()
        }
        #else
        self.health = HealthKitProvider()
        #endif

        self.hrm = HeartRateMonitor(simulated: uiTest)
        self.location = LocationTracker(simulated: uiTest)

        super.init()
    }

    // MARK: Watch HR relay (FR-8)

    /// Is the Apple Watch available to stream HR? Uses cached value to avoid
    /// synchronous IPC calls from SwiftUI body evaluation.
    var watchAvailable: Bool {
        Self.liveWatchHREnabled && !isUITestMode && watchAppInstalled
    }

    /// Activates the WCSession and caches `isWatchAppInstalled`. Called once from
    /// `CadenceApp.task{}` so it doesn't block launch (FR-8 reliability fix).
    func activateWCSession() {
        guard Self.liveWatchHREnabled, !isUITestMode, WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private var _settings: AppSettings?
    private var _modelContainer: ModelContainer?
    private var _active: ActiveWorkoutModel?

    func configureWatchSync(settings: AppSettings, container: ModelContainer,
                            active: ActiveWorkoutModel? = nil) {
        _settings = settings
        _modelContainer = container
        _active = active
    }

    func pushSettingsContext(force: Bool = false) {
        guard let settings = _settings else {
            if force { recordWatchSyncFailure("Settings unavailable") }
            return
        }
        guard let session = wcSession, session.isWatchAppInstalled else {
            if force { recordWatchSyncFailure("Watch unavailable") }
            return
        }
        let now = Date()
        watchSyncState = .syncing(now)
        let prefs = WatchSync.Preferences(
            unit: settings.unit,
            intervalColorBlind: settings.intervalColorBlind,
            restSeconds: settings.restSeconds,
            warmupMinutes: settings.warmupMinutes,
            cooldownMinutes: settings.cooldownMinutes,
            workoutSounds: settings.workoutSounds,
            recentPartnerNames: recentPartnerNames()
        )
        do {
            try session.updateApplicationContext(WatchSync.Preferences.contextDict(prefs, updatedAt: now))
            recordWatchSyncSuccess(now)
        } catch {
            recordWatchSyncFailure(error.localizedDescription)
        }
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

        guard session.isReachable else {
            watchError = "Open the companion Watch app and keep the screen on"
            return
        }

        session.sendMessage([WatchSync.Key.command: "start_workout", "type": rawType],
                            replyHandler: nil,
                            errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                self?.watchActive = false
                self?.watchError = "Watch connection failed — make sure Cladiron is open on your Watch"
                self?.watchTimeout?.invalidate()
            }
        })
        watchActive = true
        watchTimeout = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard self?.watchActive == true else { return }
                self?.watchActive = false
                self?.watchError = "No heart rate received — check that Cladiron is running on your Watch"
                self?.watchTimeout?.invalidate()
            }
        }
    }

    /// Tells the Apple Watch to end the `HKWorkoutSession` and stop streaming.
    func stopWatchWorkout() {
        watchTimeout?.invalidate(); watchTimeout = nil
        guard watchAvailable, let session = wcSession else { return }
        session.sendMessage([WatchSync.Key.command: "stop_workout"],
                            replyHandler: nil, errorHandler: nil)
        watchActive = false
        watchError = nil
    }

    private var wcSession: WCSession? {
        guard WCSession.isSupported() else { return nil }
        let s = WCSession.default
        return s.activationState == .activated ? s : nil
    }

    private func recentPartnerNames() -> [String] {
        guard let container = _modelContainer else { return [] }
        let ctx = ModelContext(container)
        var descriptor = FetchDescriptor<Person>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 6
        let people = (try? ctx.fetch(descriptor)) ?? []
        return Array(people
            .filter { !$0.isMe && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(\.name)
            .prefix(3))
    }

    private func recordWatchSyncSuccess(_ date: Date) {
        lastWatchSyncAt = date
        lastWatchSyncError = nil
        UserDefaults.standard.set(date, forKey: "settings.lastWatchSyncAt")
        watchSyncState = .synced(date)
    }

    private func recordWatchSyncFailure(_ message: String) {
        lastWatchSyncError = message
        watchSyncState = .failed(message, lastWatchSyncAt)
    }
}

// MARK: - WCSessionDelegate (FR-8)

extension AppModel: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.watchAppInstalled = session.isWatchAppInstalled
                self.pushSettingsContext()
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.watchAppInstalled = session.isWatchAppInstalled
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleWatchMessage(message)
    }

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        handleWatchMessage(message, replyHandler: replyHandler)
    }

    private func handleWatchMessage(_ message: [String: Any],
                                    replyHandler: (([String: Any]) -> Void)? = nil) {
        if message[WatchSync.Key.command] as? String == WatchSync.Key.requestSettingsSync {
            DispatchQueue.main.async { [weak self] in
                self?.pushSettingsContext(force: true)
                replyHandler?(["ack": true])
            }
            return
        }

        guard let bpm = message["bpm"] as? Double else {
            replyHandler?(["ack": false])
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.watchTimeout?.invalidate(); self.watchTimeout = nil
            self.watchError = nil
            self.hrm.injectExternalBPM(bpm)
            replyHandler?(["ack": true])
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let action = userInfo["action"] as? String else { return }
        switch action {
        case "log_set":
            handleWatchLogSet(userInfo)
        case "end_session":
            handleWatchEndSession(userInfo)
        case "discard_session":
            handleWatchDiscardSession(userInfo)
        case "set_unit":
            handleWatchSetUnit(userInfo)
        default:
            break
        }
    }

    private func handleWatchLogSet(_ info: [String: Any]) {
        guard let container = _modelContainer,
              let sid = info["session_id"] as? String,
              let sessionID = UUID(uuidString: sid) else { return }
        let ctx = ModelContext(container)
        do {
            let sessions = try ctx.fetch(FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { $0.id == sessionID }
            ))
            let session: WorkoutSession
            if let existing = sessions.first {
                session = existing
            } else {
                session = try WorkoutRepository.createSession(title: "Strength", in: ctx)
                session.id = sessionID
                try ctx.save()
            }
            guard let exName = info["exercise"] as? String,
                  let weight = info["weight"] as? Double,
                  let reps = info["reps"] as? Int else { return }
            let exercise = try WorkoutRepository.findOrCreateExercise(named: exName, in: ctx)
            let isWarmup = info["is_warmup"] as? Bool ?? false
            let performedBy: Person?
            if let pid = info["performed_by_id"] as? String, let puid = UUID(uuidString: pid) {
                performedBy = try ctx.fetch(FetchDescriptor<Person>(
                    predicate: #Predicate { $0.id == puid }
                )).first
            } else if let pname = info["performed_by"] as? String {
                performedBy = try WorkoutRepository.findOrCreatePerson(named: pname, in: ctx)
            } else {
                performedBy = nil
            }
            if let sidStr = info["set_id"] as? String, let setID = UUID(uuidString: sidStr) {
                let existing = try ctx.fetch(FetchDescriptor<SetEntry>(
                    predicate: #Predicate { $0.id == setID }
                ))
                guard existing.isEmpty else { return }
            }
            _ = try WorkoutRepository.addSet(
                to: session, exercise: exercise, weightKg: weight, reps: reps,
                isWarmup: isWarmup, performedBy: performedBy, in: ctx
            )
            NotificationCenter.default.post(name: .workoutHistoryChanged, object: nil)
        } catch {}
    }

    private func handleWatchEndSession(_ info: [String: Any]) {
        guard let container = _modelContainer,
              let sid = info["session_id"] as? String,
              let sessionID = UUID(uuidString: sid) else { return }
        // The phone's live workout ends only by an explicit tap on the phone —
        // a watch-relayed end may never finalize it (launch-blockers Phase 1d).
        guard WatchSessionEndPolicy.shouldApplyEnd(
            sessionID: sessionID,
            phoneActiveID: _active?.strengthSession?.id) else { return }
        let ctx = ModelContext(container)
        do {
            let sessions = try ctx.fetch(FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { $0.id == sessionID }
            ))
            guard let session = sessions.first else { return }
            session.endedAt = Date()
            if let cs = info["cooldown_seconds"] as? Int {
                session.cooldownSeconds = Double(cs)
            }
            try ctx.save()
            NotificationCenter.default.post(name: .workoutHistoryChanged, object: nil)
        } catch {}
    }

    private func handleWatchDiscardSession(_ info: [String: Any]) {
        guard let container = _modelContainer,
              let sid = info["session_id"] as? String,
              let sessionID = UUID(uuidString: sid) else { return }
        let ctx = ModelContext(container)
        do {
            let sessions = try ctx.fetch(FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { $0.id == sessionID }
            ))
            for s in sessions { ctx.delete(s) }
            try ctx.save()
            NotificationCenter.default.post(name: .workoutHistoryChanged, object: nil)
        } catch {}
    }

    private func handleWatchSetUnit(_ info: [String: Any]) {
        guard let raw = info["value"] as? String,
              let unit = MeasurementUnitPreference(rawValue: raw) else { return }
        _settings?.unit = unit
    }
}

// MARK: - Watch sync notifications

extension Notification.Name {
    static let watchSetLogged = Notification.Name("watch.setLogged")
    static let watchSessionEnded = Notification.Name("watch.sessionEnded")
}
