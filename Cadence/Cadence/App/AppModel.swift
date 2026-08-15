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
@MainActor @Observable
final class AppModel: NSObject, @unchecked Sendable {
    private static let liveWatchHREnabled = true

    let health: HealthDataProviding
    let hrm: HeartRateMonitor
    let location: LocationTracker
    let isUITestMode: Bool

    /// Whether the Apple Watch is actively streaming HR (FR-8).
    private(set) var watchActive: Bool = false
    /// When set, the watch was told to start but never confirmed.
    private(set) var watchError: String?
    let watchHRRelay: WatchHRRelay
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

    @MainActor
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
        self.watchHRRelay = WatchHRRelay()

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
        var context = WatchSync.Preferences.contextDict(prefs, updatedAt: now)
        if let todayPlan = watchTodayPlan(settings: settings, updatedAt: now) {
            context.merge(WatchSync.TodayPlan.contextDict(todayPlan)) { _, new in new }
        }
        if let container = _modelContainer {
            let ctx = ModelContext(container)
            let exercises = (try? WorkoutRepository.allExercises(ctx)) ?? []
            context[WatchSync.Key.customExercises] = WatchSync.customExercisesContext(exercises)
        }
        do {
            try session.updateApplicationContext(context)
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

        let requestID = UUID()
        watchHRRelay.begin(requestID: requestID)
        session.sendMessage([WatchSync.Key.command: "start_workout", "type": rawType, "requestID": requestID.uuidString],
                            replyHandler: { [weak self] reply in
                                Task { @MainActor in
                                    guard let self,
                                          (reply["requestID"] as? String).flatMap(UUID.init(uuidString:)) == requestID,
                                          let accepted = reply["accepted"] as? Bool else { return }
                                    if accepted {
                                        self.watchHRRelay.acknowledged()
                                    } else {
                                        let reason = (reply["rejection"] as? String) ?? "unavailable"
                                        self.watchHRRelay.fail("Apple Watch rejected heart-rate monitoring (\(reason))")
                                    }
                                }
                            },
                            errorHandler: { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.watchActive = false
                self.watchError = "Watch connection failed — make sure Cladiron is open on your Watch"
                self.watchTimeout?.invalidate()
            }
        })
        watchActive = false
        watchTimeout = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.watchHRRelay.freshBPM == nil else { return }
                self.watchHRRelay.timeout()
                self.watchActive = false
                self.watchError = "No heart rate received — check that Cladiron is running on your Watch"
                self.watchTimeout?.invalidate()
            }
        }
    }

    /// Tells the Apple Watch to end the `HKWorkoutSession` and stop streaming.
    func stopWatchWorkout() {
        watchTimeout?.invalidate(); watchTimeout = nil
        watchHRRelay.cancel()
        guard watchAvailable, let session = wcSession else { return }
        var message: [String: Any] = [WatchSync.Key.command: "stop_workout"]
        if let requestID = watchHRRelay.activeRequestID { message["requestID"] = requestID.uuidString }
        session.sendMessage(message,
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

    private func watchTodayPlan(settings: AppSettings, updatedAt: Date) -> WatchSync.TodayPlan? {
        guard let container = _modelContainer else { return nil }
        let ctx = ModelContext(container)
        let sessions = (try? ctx.fetch(FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
        let cardio = (try? ctx.fetch(FetchDescriptor<CardioWorkout>(
            sortBy: [SortDescriptor(\.start, order: .reverse)]
        ))) ?? []
        let assessments = (try? ctx.fetch(FetchDescriptor<Assessment>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
        let policy: PlanningConstraintPolicy = settings.isPlanOverrideActive(now: updatedAt) ? .meetDeficits : .safe
        let snapshot = HomeCoachModel.snapshot(
            sessions: sessions,
            cardio: cardio,
            assessments: assessments,
            readiness: [],
            goal: settings.trainingGoal,
            experience: settings.experienceLevel,
            formula: settings.formula,
            schedule: settings.coachSchedulePreferences,
            profile: settings.coachPreferenceProfile,
            userAge: settings.userAge,
            now: updatedAt,
            constraintPolicy: policy
        )
        return WatchSync.TodayPlan.from(day: snapshot.plan.today, updatedAt: updatedAt)
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

extension AppModel: @preconcurrency WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            let installed = session.isWatchAppInstalled
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.watchAppInstalled = installed
                self.pushSettingsContext()
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        let installed = session.isWatchAppInstalled
        Task { @MainActor [weak self] in
            self?.watchAppInstalled = installed
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
            Task { @MainActor [weak self] in
                self?.pushSettingsContext(force: true)
            }
            replyHandler?(["ack": true])
            return
        }

        guard let bpm = message["bpm"] as? Double,
              let requestIDString = message["requestID"] as? String,
              let requestID = UUID(uuidString: requestIDString) else {
            replyHandler?(["ack": false])
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.watchTimeout?.invalidate(); self.watchTimeout = nil
            self.watchError = nil
            if self.watchHRRelay.receive(bpm: Int(bpm), requestID: requestID) {
                self.watchActive = true
                self.hrm.injectExternalBPM(bpm)
            }
        }
        replyHandler?(["ack": true])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let action = userInfo["action"] as? String else { return }
        switch action {
        case "log_set", "end_session", "discard_session", "delete_exercise", "delete_set":
            handleWatchStrengthMutation(userInfo)
        case "set_unit":
            handleWatchSetUnit(userInfo)
        case "set_distance_unit":
            handleWatchSetDistanceUnit(userInfo)
        default:
            break
        }
    }

    private func handleWatchStrengthMutation(_ info: [String: Any]) {
        guard let container = _modelContainer else { return }
        let ctx = ModelContext(container)
        do {
            let action = try WatchStrengthSyncApplier.apply(
                userInfo: info,
                in: ctx,
                phoneActiveID: _active?.strengthSession?.id
            )
            guard action != .ignored else { return }
            switch action {
            case .logSet:
                NotificationCenter.default.post(name: .watchSetLogged, object: nil)
            case .endSession:
                NotificationCenter.default.post(name: .watchSessionEnded, object: nil)
            default:
                break
            }
            NotificationCenter.default.post(name: .workoutHistoryChanged, object: nil)
        } catch {}
    }

    private func handleWatchSetUnit(_ info: [String: Any]) {
        guard let raw = info["value"] as? String,
              let unit = MeasurementUnitPreference(rawValue: raw) else { return }
        _settings?.unit = unit
    }

    private func handleWatchSetDistanceUnit(_ info: [String: Any]) {
        guard let raw = info["value"] as? String,
              let du = DistanceUnitPreference(rawValue: raw) else { return }
        _settings?.distanceUnit = du
    }
}

// MARK: - Watch sync notifications

extension Notification.Name {
    static let watchSetLogged = Notification.Name("watch.setLogged")
    static let watchSessionEnded = Notification.Name("watch.sessionEnded")
}
