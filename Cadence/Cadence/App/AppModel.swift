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
    /// When a `start_workout` is rejected `.alreadyActive`, this is armed for the
    /// 1.2 s teardown window so the stop-then-retry-once fires only while the
    /// user is still on the HR screen (any new start/stop disarms it).
    private var watchRetryArmed = false
    /// UI-test seam (`-uiTestWatchStop`): record every `stopWatchWorkout()` call
    /// into `UserDefaults("uitest.watchStopCount")` so the iPhone smoke test can
    /// assert the cardio end paths actually stop the watch session.
    private let recordsWatchStop: Bool
    /// Only meaningful while `recordsWatchStop`; the running call count surfaced
    /// to the smoke test through the same UserDefaults key.
    private var watchStopCount: Int = 0

    /// Cached once at launch — avoids hitting `WCSession.default.isWatchAppInstalled`
    /// (a synchronous IPC call) from SwiftUI body evaluation.
    private(set) var watchAppInstalled: Bool = false
    private(set) var watchSyncState: WatchSync.Status = .idle
    private(set) var lastWatchSyncAt: Date? = UserDefaults.standard.object(forKey: "settings.lastWatchSyncAt") as? Date
    private(set) var lastWatchSyncError: String?
    private let watchSessionDelegate: WatchSessionDelegateProxy

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
        self.recordsWatchStop = args.contains("-uiTestWatchStop")
        self.watchStopCount = self.recordsWatchStop
            ? UserDefaults.standard.integer(forKey: "uitest.watchStopCount")
            : 0
        self.watchSessionDelegate = WatchSessionDelegateProxy()

        super.init()
        self.watchSessionDelegate.owner = self
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
        // WatchConnectivity invokes its delegate on a private queue. Keep the
        // Objective-C delegate nonisolated and hop into AppModel's main actor.
        session.delegate = watchSessionDelegate
        session.activate()
    }

    #if DEBUG
    var watchSessionDelegateForTesting: any WCSessionDelegate { watchSessionDelegate }
    #endif

    private var _settings: AppSettings?
    private var _modelContainer: ModelContainer?
    private var _active: ActiveWorkoutModel?
    /// The most recently computed Home plan. Foreground/settings sync reuses
    /// this value rather than walking SwiftData and rebuilding the coach plan
    /// synchronously during an unlock transition.
    private var cachedTodayPlan: WatchSync.TodayPlan?

    #if DEBUG
    var cachedTodayPlanForTesting: WatchSync.TodayPlan? { cachedTodayPlan }
    #endif

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
        if let todayPlan = cachedTodayPlan {
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

    /// Publishes the plan Home already computed asynchronously. This is kept
    /// separate from settings sync so a foreground transition never has to
    /// fetch the complete workout history just to update the Watch.
    func updateWatchTodayPlan(_ plan: WatchSync.TodayPlan) {
        cachedTodayPlan = plan
        guard let session = wcSession, session.isWatchAppInstalled else { return }
        var context = session.applicationContext
        context.merge(WatchSync.TodayPlan.contextDict(plan)) { _, new in new }
        do {
            try session.updateApplicationContext(context)
            recordWatchSyncSuccess(plan.updatedAt)
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
        watchRetryArmed = false
        performWatchStart(rawType: rawType, retryType: rawType, allowsRetry: true)
    }

    private func performWatchStart(rawType: String, retryType: String, allowsRetry: Bool) {
        guard watchAvailable, let session = wcSession else { return }
        watchError = nil
        watchTimeout?.invalidate()

        guard session.isReachable else {
            watchError = "Open the companion Watch app and keep the screen on"
            return
        }

        let requestID = UUID()
        watchHRRelay.begin(requestID: requestID)
        session.sendMessage(
            [WatchSync.Key.command: "start_workout", "type": rawType, "requestID": requestID.uuidString],
            replyHandler: Self.watchReplyHandler(owner: self, requestID: requestID,
                                                 retryType: retryType, allowsRetry: allowsRetry),
            errorHandler: Self.watchErrorHandler(owner: self))
        watchActive = false
        watchTimeout = Timer.scheduledTimer(
            withTimeInterval: 15,
            repeats: false,
            block: Self.watchTimeoutHandler(owner: self))
    }

    nonisolated private static func watchReplyHandler(owner: AppModel, requestID: UUID,
                                                      retryType: String, allowsRetry: Bool) -> ([String: Any]) -> Void {
        { reply in
            let matchesRequest = (reply["requestID"] as? String).flatMap(UUID.init(uuidString:)) == requestID
            let accepted = reply["accepted"] as? Bool
            let reason = (reply["rejection"] as? String) ?? "unavailable"
            let rejection = WatchHRRejection(rawValue: reason)
            Task { @MainActor [weak owner] in
                guard let owner, matchesRequest, let accepted else { return }
                owner.handleWatchStartReply(accepted: accepted, rejection: rejection,
                                            retryType: retryType, allowsRetry: allowsRetry)
            }
        }
    }

    /// Reacts to a `start_workout` reply. A stale `.alreadyActive` rejection is
    /// the failure this phase fixes: tear the leaked watch session down and
    /// start once more with a fresh requestID after a short beat. Any other
    /// rejection — including a second `.alreadyActive` on the retry — surfaces
    /// the error text so the user sees a real message instead of a silent hang.
    private func handleWatchStartReply(accepted: Bool, rejection: WatchHRRejection?,
                                       retryType: String, allowsRetry: Bool) {
        if accepted {
            watchHRRelay.acknowledged()
            watchRetryArmed = false
            return
        }
        guard WatchHRRelay.shouldRetryAfterStop(rejection: rejection),
              allowsRetry, !watchRetryArmed else {
            watchHRRelay.fail("Apple Watch rejected heart-rate monitoring (\(rejection?.rawValue ?? "unavailable"))")
            return
        }
        stopWatchWorkout()
        watchRetryArmed = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self, self.watchRetryArmed else { return }
            self.watchRetryArmed = false
            self.performWatchStart(rawType: retryType, retryType: retryType, allowsRetry: false)
        }
    }

    nonisolated private static func watchErrorHandler(owner: AppModel) -> (Error) -> Void {
        { _ in
            Task { @MainActor [weak owner] in
                guard let owner else { return }
                owner.watchActive = false
                owner.watchError = "Watch connection failed — make sure Cladiron is open on your Watch"
                owner.watchTimeout?.invalidate()
            }
        }
    }

    nonisolated private static func watchTimeoutHandler(owner: AppModel) -> @Sendable (Timer) -> Void {
        { _ in
            Task { @MainActor [weak owner] in
                guard let owner, owner.watchHRRelay.freshBPM == nil else { return }
                owner.watchHRRelay.timeout()
                owner.watchActive = false
                owner.watchError = "No heart rate received — check that Cladiron is running on your Watch"
                owner.watchTimeout?.invalidate()
            }
        }
    }

    /// Tells the Apple Watch to end the `HKWorkoutSession` and stop streaming.
    func stopWatchWorkout() {
        watchRetryArmed = false
        watchTimeout?.invalidate(); watchTimeout = nil
        watchHRRelay.cancel()
        if recordsWatchStop {
            watchStopCount += 1
            UserDefaults.standard.set(watchStopCount, forKey: "uitest.watchStopCount")
        }
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

// MARK: - Main-actor WatchConnectivity handlers

extension AppModel {
    fileprivate func watchActivationCompleted(installed: Bool) {
        watchAppInstalled = installed
        pushSettingsContext()
    }

    fileprivate func watchStateChanged(installed: Bool) {
        watchAppInstalled = installed
    }

    fileprivate func handleWatchMessage(_ message: [String: Any],
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

    fileprivate func handleWatchUserInfo(_ userInfo: [String: Any]) {
        guard let action = userInfo["action"] as? String else { return }
        let payload = UncheckedWatchUserInfo(value: userInfo)
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch action {
            case "log_set", "end_session", "discard_session", "delete_exercise", "delete_set":
                self.handleWatchStrengthMutation(payload.value)
            case "set_unit":
                self.handleWatchSetUnit(payload.value)
            case "set_distance_unit":
                self.handleWatchSetDistanceUnit(payload.value)
            default:
                break
            }
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

/// WatchConnectivity calls its delegate from private queues. This object must
/// remain nonisolated at the Objective-C boundary; every app-state mutation is
/// explicitly scheduled on AppModel's main actor.
private final class WatchSessionDelegateProxy: NSObject, WCSessionDelegate, @unchecked Sendable {
    weak var owner: AppModel?

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        guard activationState == .activated else { return }
        let installed = session.isWatchAppInstalled
        Task { @MainActor [weak owner] in
            owner?.watchActivationCompleted(installed: installed)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        let installed = session.isWatchAppInstalled
        Task { @MainActor [weak owner] in
            owner?.watchStateChanged(installed: installed)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let payload = UncheckedWatchUserInfo(value: message)
        Task { @MainActor [weak owner] in
            owner?.handleWatchMessage(payload.value)
        }
    }

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        let payload = UncheckedWatchUserInfo(value: message)
        let reply = UncheckedWatchReplyHandler(value: replyHandler)
        Task { @MainActor [weak owner] in
            owner?.handleWatchMessage(payload.value, replyHandler: reply.value)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let payload = UncheckedWatchUserInfo(value: userInfo)
        Task { @MainActor [weak owner] in
            owner?.handleWatchUserInfo(payload.value)
        }
    }
}

/// `WCSessionDelegate` guarantees property-list payloads, but its Objective-C
/// API predates `Sendable`. This wrapper documents that framework guarantee so
/// the callback can hand the immutable dictionary to the main actor.
private struct UncheckedWatchUserInfo: @unchecked Sendable {
    let value: [String: Any]
}

private struct UncheckedWatchReplyHandler: @unchecked Sendable {
    let value: ([String: Any]) -> Void
}

// MARK: - Watch sync notifications

extension Notification.Name {
    static let watchSetLogged = Notification.Name("watch.setLogged")
    static let watchSessionEnded = Notification.Name("watch.sessionEnded")
}
