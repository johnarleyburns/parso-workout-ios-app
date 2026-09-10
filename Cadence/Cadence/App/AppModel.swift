import Foundation
import SwiftUI
import Observation
import SwiftData
import WatchConnectivity
import CloudKit
import CoreData
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
    /// Monotonic stamp shared by immediate and guaranteed-background control
    /// messages. The Watch uses it to ignore a delayed stop from an older
    /// workout after a newer workout has already begun.
    private var lastWatchHRCommandIssuedAt = UserDefaults.standard.double(forKey: "watchHR.lastCommandIssuedAt")
    /// When a `start_workout` is rejected `.alreadyActive`, this is armed for the
    /// 1.2 s teardown window so the stop-then-retry-once fires only while the
    /// user is still on the HR screen (any new start/stop disarms it).
    private var watchRetryArmed = false
    /// A start tapped during WCSession activation is held until activation has
    /// completed. Sending before activation is silently dropped by some OS
    /// releases, which used to leave the HR gate waiting forever.
    private var pendingWatchStartType: String?
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
    private(set) var cloudKitAccountAvailability: CloudKitAccountAvailability = .checking
    private(set) var isRestoringCloudKitHistory = false
    private(set) var cloudKitRestoreNotice: String?
    private var cloudKitEventObserver: NSObjectProtocol?
    private var cloudKitRestoreNoticeTask: Task<Void, Never>?
    /// CloudKit can deliver several import events while a new device is being
    /// hydrated. Keep Home in its lightweight placeholder state until the
    /// import burst has been quiet for a moment, then let it rebuild once.
    private var cloudKitImportQuietTask: Task<Void, Never>?

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

    /// Checks the Apple-ID account that backs the private SwiftData store.
    /// CloudKit account lookup is asynchronous and never blocks the first
    /// frame; UI tests use a deterministic available state.
    func refreshCloudKitAccountStatus() {
        guard !isUITestMode else {
            cloudKitAccountAvailability = .available
            return
        }
        cloudKitAccountAvailability = .checking
        CKContainer(identifier: CadenceStore.cloudKitContainerID).accountStatus { [weak self] status, _ in
            Task { @MainActor [weak self] in
                self?.cloudKitAccountAvailability = CloudKitAccountGate.availability(for: status.rawValue)
            }
        }
    }

    /// Observes Core Data's CloudKit import events. SwiftData owns the
    /// underlying store, but it forwards these notifications; this gives the UI
    /// an honest restore indicator without pretending CloudKit exposes byte-level
    /// progress.
    func startCloudKitHistoryMonitoring() {
        guard !isUITestMode, cloudKitEventObserver == nil else { return }
        cloudKitEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main) { [weak self] notification in
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event,
                      event.type == .import else { return }
                let isInProgress = event.endDate == nil
                let succeeded = event.succeeded
                Task { @MainActor [weak self] in
                    self?.applyCloudKitImport(isInProgress: isInProgress, succeeded: succeeded)
                }
            }
    }

    private func applyCloudKitImport(isInProgress: Bool, succeeded: Bool) {
        cloudKitRestoreNoticeTask?.cancel()
        cloudKitImportQuietTask?.cancel()
        if isInProgress {
            cloudKitRestoreNotice = nil
            isRestoringCloudKitHistory = true
            return
        }

        // A single logical restore may be reported as several short imports.
        // Do not release Home into an expensive full-history coach rebuild for
        // every one of those events.
        cloudKitImportQuietTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.isRestoringCloudKitHistory = false
            self.cloudKitRestoreNotice = succeeded
                ? "iCloud history updated"
                : "iCloud history update paused"
            let notice = self.cloudKitRestoreNotice
            self.cloudKitRestoreNoticeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, self?.cloudKitRestoreNotice == notice else { return }
                self?.cloudKitRestoreNotice = nil
            }
        }
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
        if !isUITestMode, WCSession.isSupported(), WCSession.default.activationState != .activated {
            pendingWatchStartType = rawType
            activateWCSession()
            return
        }
        performWatchStart(rawType: rawType, retryType: rawType, allowsRetry: true)
    }

    private func performWatchStart(rawType: String, retryType: String, allowsRetry: Bool) {
        guard watchAvailable, let session = wcSession else {
            watchError = "Apple Watch is unavailable — open Cladiron on your Watch and try again"
            return
        }
        watchError = nil
        watchTimeout?.invalidate()

        guard session.isReachable else {
            watchError = "Open the companion Watch app and keep the screen on"
            return
        }

        let requestID = UUID()
        watchHRRelay.begin(requestID: requestID)
        let command = WatchHRCommand(action: .start, requestID: requestID,
                                     workoutType: rawType, issuedAt: nextWatchHRCommandIssuedAt())
        // Keep a durable copy in case the watch is reachable only briefly or
        // the immediate message is lost while the companion launches. The
        // watch's command handler makes this duplicate idempotent.
        session.transferUserInfo(command.payload)
        session.sendMessage(
            command.payload,
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
            let activeRequestID = (reply["activeRequestID"] as? String).flatMap(UUID.init(uuidString:))
            Task { @MainActor [weak owner] in
                guard let owner, matchesRequest, let accepted else { return }
                owner.handleWatchStartReply(accepted: accepted, rejection: rejection,
                                            activeRequestID: activeRequestID,
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
                                       activeRequestID: UUID?,
                                       retryType: String, allowsRetry: Bool) {
        if accepted {
            watchHRRelay.acknowledged()
            watchRetryArmed = false
            return
        }
        guard WatchHRRelay.shouldRetryAfterStop(rejection: rejection),
              let activeRequestID, allowsRetry, !watchRetryArmed else {
            watchHRRelay.fail("Apple Watch rejected heart-rate monitoring (\(rejection?.rawValue ?? "unavailable"))")
            return
        }
        stopWatchWorkout(targetRequestID: activeRequestID)
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
        stopWatchWorkout(targetRequestID: watchHRRelay.activeRequestID)
    }

    /// Sends both an immediate stop and an ordered, guaranteed-background copy.
    /// The request ID scopes a delayed copy to the session it was meant for.
    private func stopWatchWorkout(targetRequestID: UUID?) {
        watchRetryArmed = false
        watchTimeout?.invalidate(); watchTimeout = nil
        watchHRRelay.cancel()
        if recordsWatchStop {
            watchStopCount += 1
            UserDefaults.standard.set(watchStopCount, forKey: "uitest.watchStopCount")
        }
        watchActive = false
        watchError = nil
        guard let targetRequestID, let session = wcSession else { return }
        let command = WatchHRCommand(action: .stop, requestID: targetRequestID,
                                     issuedAt: nextWatchHRCommandIssuedAt())
        // Apple guarantees queued user-info delivery even if either app is
        // suspended or temporarily unreachable. The matching request ID and
        // command timestamp make the immediate/background duplicate harmless.
        session.transferUserInfo(command.payload)
        if session.isReachable {
            session.sendMessage(command.payload, replyHandler: nil, errorHandler: nil)
        }
    }

    private func nextWatchHRCommandIssuedAt(now: Date = Date()) -> TimeInterval {
        let next = WatchHRCommand.nextIssuedAt(now: now.timeIntervalSince1970,
                                               after: lastWatchHRCommandIssuedAt == 0 ? nil : lastWatchHRCommandIssuedAt)
        lastWatchHRCommandIssuedAt = next
        UserDefaults.standard.set(next, forKey: "watchHR.lastCommandIssuedAt")
        return next
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
        if installed, let rawType = pendingWatchStartType {
            pendingWatchStartType = nil
            performWatchStart(rawType: rawType, retryType: rawType, allowsRetry: true)
        }
    }

    fileprivate func watchStateChanged(installed: Bool) {
        watchAppInstalled = installed
    }

    fileprivate func handleWatchMessage(_ message: [String: Any],
                                         replyHandler: (([String: Any]) -> Void)? = nil) {
        if let requestIDString = message["requestID"] as? String,
           let requestID = UUID(uuidString: requestIDString),
           let accepted = message["accepted"] as? Bool {
            // A queued start is acknowledged by a follow-up message from the
            // watch. It has the same request ID as the immediate reply and is
            // therefore safe to apply after either delivery wins the race.
            if accepted, requestID == watchHRRelay.activeRequestID {
                watchTimeout?.invalidate(); watchTimeout = nil
                watchError = nil
                watchHRRelay.acknowledged()
            }
            replyHandler?(accepted ? ["ack": true] : ["ack": false])
            return
        }
        if message["action"] as? String == "cardio_completion" {
            let accepted = handleWatchCardioCompletion(message)
            replyHandler?(accepted ? completionAck(for: message) : ["ack": false])
            return
        }
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
            case "cardio_completion":
                _ = self.handleWatchCardioCompletion(payload.value)
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

    @discardableResult
    private func handleWatchCardioCompletion(_ info: [String: Any]) -> Bool {
        guard let data = info["payload"] as? Data,
              let completion = try? WatchCardioCompletion.decode(data),
              let container = _modelContainer else { return false }
        let ctx = ModelContext(container)
        do {
            _ = try WorkoutRepository.ingest(completion, in: ctx)
            let ack: [String: Any] = ["action": "cardio_completion_ack", "id": completion.id.uuidString]
            if let session = wcSession {
                session.transferUserInfo(ack)
                if session.isReachable { session.sendMessage(ack, replyHandler: nil, errorHandler: nil) }
            }
            NotificationCenter.default.post(name: .workoutHistoryChanged, object: nil)
            return true
        } catch {
            // Keep the watch payload queued; a later delivery can retry it.
            return false
        }
    }

    private func completionAck(for info: [String: Any]) -> [String: Any] {
        guard let data = info["payload"] as? Data,
              let completion = try? WatchCardioCompletion.decode(data) else { return ["ack": false] }
        return ["ack": true, "action": "cardio_completion_ack", "id": completion.id.uuidString]
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
