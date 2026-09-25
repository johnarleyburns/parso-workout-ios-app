import Foundation
import SwiftUI
import Observation
import SwiftData
import WatchConnectivity
import HealthKit
import CloudKit
import CoreData
import CadenceCore
import CadenceFeatures
import os
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
    private static let performanceLog = OSLog(subsystem: "guru.parso.cladiron", category: "AppPerformance")
    /// WatchConnectivity's application-context write can synchronously cross
    /// into the paired device. Keep that IPC off the main actor so a visible
    /// "Syncing to Watch" toast never coincides with a frozen Home screen.
    private static let watchContextQueue = DispatchQueue(
        label: "guru.parso.cladiron.watch-context",
        qos: .utility)

    enum HealthSyncStatus: Equatable, Sendable {
        case idle
        case syncing
        case completed(Date, insertedCount: Int)
        case failed(String)

        var isInProgress: Bool {
            if case .syncing = self { return true }
            return false
        }

        var detailText: String {
            switch self {
            case .idle: return "Not run yet"
            case .syncing: return "Checking Apple Health…"
            case .completed(_, let insertedCount):
                return insertedCount == 0
                    ? "Checked; no new workouts"
                    : "Imported (insertedCount) workout\(insertedCount == 1 ? "" : "s")"
            case .failed(let message): return "Couldn’t check Apple Health: \(message)"
            }
        }
    }

    enum CloudKitImportStatus: Equatable, Sendable {
        case idle
        case updating
        case completed(Date)
        case failed(Date)

        var detailText: String {
            switch self {
            case .idle: return "No recent import"
            case .updating: return "Updating private history…"
            case .completed: return "Private history up to date"
            case .failed: return "Update paused — open Diagnostics"
            }
        }
    }

    let health: HealthDataProviding
    let hrm: HeartRateMonitor
    let location: LocationTracker
    let isUITestMode: Bool

    /// Whether the Apple Watch is actively streaming HR (FR-8).
    private(set) var watchActive: Bool = false
    /// True from the user's request until the Watch produces a live sample or
    /// the connection attempt fails. This keeps the HR gate honest while
    /// WatchConnectivity activates or the Watch launches its workout session.
    private(set) var watchStartInProgress: Bool = false
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
    /// The start request still waiting for the Watch's first answer. Both the
    /// immediate reply and the Watch's answer to the queued copy (the only
    /// answer a Watch app the phone launched can give) may arrive; the first
    /// decides retry or failure, and later ones only confirm.
    private struct PendingWatchStart {
        let requestID: UUID
        let retryType: String
        let allowsRetry: Bool
    }
    @ObservationIgnored private var pendingWatchStart: PendingWatchStart?
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
    private(set) var cloudKitImportStatus: CloudKitImportStatus = .idle
    private var cloudKitEventObserver: NSObjectProtocol?
    /// CloudKit can deliver several import events while a new device is being
    /// hydrated. Keep Home in its lightweight placeholder state until the
    /// import burst has been quiet for a moment, then let it rebuild once.
    private var cloudKitImportQuietTask: Task<Void, Never>?

    /// Last time we ingested HealthKit workouts (FR-2.1), persisted across runs.
    var healthSyncStatus: HealthSyncStatus = .idle
    /// Published while Home recomputes its ephemeral coach projection so the
    /// operation is visible in Settings → Transparency & Control without
    /// inserting transient content into the Home layout.
    var coachRefreshInProgress = false

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

    /// A user-facing description of the current Watch connection step. The HR
    /// gate shows this beside a spinner so a slow WatchConnectivity handoff
    /// never looks like a frozen screen.
    var watchConnectionStatus: String {
        if let watchError { return watchError }
        switch watchHRRelay.state {
        case .launchingWatchApp:
            return "Opening Cladiron on your Apple Watch…"
        case .connecting:
            return "Connecting to your Apple Watch…"
        case .waitingForSample:
            return "Apple Watch connected · waiting for the first heart-rate reading…"
        case .live:
            return "Live heart rate from Apple Watch"
        case .timedOut(let message), .failed(let message):
            return message
        case .unavailable(let reason):
            if watchStartInProgress { return "Preparing the Apple Watch connection…" }
            return reason
        case .actionRequired(let message):
            if watchStartInProgress { return "Preparing the Apple Watch connection…" }
            return message
        }
    }

    var watchConnectionInProgress: Bool {
        watchStartInProgress
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
    /// Legacy Watch Today-plan cache retained only for migration/tests. New
    /// builds do not populate it from the Home coach pipeline.
    private var cachedTodayPlan: WatchSync.TodayPlan?
    private var watchPayloadTask: Task<Void, Never>?
    private var lastWatchPayloadFingerprint: Int?

    private struct WatchPayloadSnapshot: Sendable {
        let customExercises: [WatchSync.CustomExercise]
        let recentPartnerNames: [String]
    }

    /// WCSession and its property-list dictionary are Foundation reference
    /// values, but the serialized queue is the sole owner of this handoff.
    /// Keeping the unchecked boundary here avoids pushing non-Sendable SDK
    /// types back onto the main actor just to perform the IPC write.
    private struct WatchContextWrite: @unchecked Sendable {
        let session: WCSession
        let context: [String: Any]
    }

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
        let signpostID = OSSignpostID(log: Self.performanceLog)
        os_signpost(.event, log: Self.performanceLog, name: "cloudKitImportEvent", signpostID: signpostID,
                    "inProgress=%{public}d succeeded=%{public}d", isInProgress, succeeded)
        cloudKitImportQuietTask?.cancel()
        if isInProgress {
            cloudKitImportStatus = .updating
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
            self.cloudKitImportStatus = succeeded ? .completed(Date()) : .failed(Date())
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
        let basePreferences = WatchSync.Preferences(
            unit: settings.unit,
            intervalColorBlind: settings.intervalColorBlind,
            restSeconds: settings.restSeconds,
            warmupMinutes: settings.warmupMinutes,
            cooldownMinutes: settings.cooldownMinutes,
            workoutSounds: settings.workoutSounds,
            recentPartnerNames: []
        )
        let container = _modelContainer
        watchPayloadTask?.cancel()
        watchPayloadTask = Task { [weak self] in
            let signpostID = OSSignpostID(log: Self.performanceLog)
            os_signpost(.begin, log: Self.performanceLog, name: "watchPayloadBuild", signpostID: signpostID)
            let payload = await Task.detached(priority: .utility) {
                guard let container else {
                    return WatchPayloadSnapshot(customExercises: [], recentPartnerNames: [])
                }
                let context = ModelContext(container)
                let exercises = (try? WorkoutRepository.allExercises(context)) ?? []
                var peopleDescriptor = FetchDescriptor<Person>(
                    sortBy: [SortDescriptor(\Person.updatedAt, order: .reverse)])
                peopleDescriptor.fetchLimit = 6
                let people = (try? context.fetch(peopleDescriptor)) ?? []
                let names = Array(people
                    .filter { !$0.isMe && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .map(\.name)
                    .prefix(3))
                return WatchPayloadSnapshot(
                    customExercises: exercises.filter(\.isCustom).map(WatchSync.CustomExercise.init),
                    recentPartnerNames: names)
            }.value
            os_signpost(.end, log: Self.performanceLog, name: "watchPayloadBuild", signpostID: signpostID)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.finishWatchSettingsContext(basePreferences: basePreferences,
                                                payload: payload, at: now,
                                                force: force, session: session)
            }
        }
    }

    private func finishWatchSettingsContext(basePreferences: WatchSync.Preferences,
                                            payload: WatchPayloadSnapshot,
                                            at date: Date,
                                            force: Bool,
                                            session: WCSession) {
        var prefs = basePreferences
        prefs.recentPartnerNames = payload.recentPartnerNames
        var fingerprint = Hasher()
        fingerprint.combine(prefs.unit.rawValue)
        fingerprint.combine(prefs.intervalColorBlind)
        fingerprint.combine(prefs.restSeconds)
        fingerprint.combine(prefs.warmupMinutes)
        fingerprint.combine(prefs.cooldownMinutes)
        fingerprint.combine(prefs.workoutSounds)
        fingerprint.combine(prefs.recentPartnerNames)
        for exercise in payload.customExercises.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            fingerprint.combine(exercise.id)
            fingerprint.combine(exercise.name)
            fingerprint.combine(exercise.updatedAt)
            fingerprint.combine(exercise.primaryMuscles)
            fingerprint.combine(exercise.secondaryMuscles)
        }
        let value = fingerprint.finalize()
        guard force || lastWatchPayloadFingerprint != value else {
            watchSyncState = .synced(lastWatchSyncAt ?? date)
            return
        }
        lastWatchPayloadFingerprint = value

        var context = WatchSync.Preferences.contextDict(prefs, updatedAt: date)
        context[WatchSync.Key.customExercises] = payload.customExercises.map(\.propertyList)
        // Explicitly remove the retired weekly plan keys. A context is merged
        // on the receiving side, so merely omitting them would leave a stale
        // plan from an older app build visible on the Watch.
        context.removeValue(forKey: WatchSync.Key.todayPlanSessions)
        context.removeValue(forKey: WatchSync.Key.todayPlanUpdatedAt)
        enqueueWatchContextWrite(context, on: session, at: date)
    }

    private func enqueueWatchContextWrite(_ context: [String: Any],
                                          on session: WCSession,
                                          at date: Date) {
        let write = WatchContextWrite(session: session, context: context)
        Self.watchContextQueue.async {
            do {
                try write.session.updateApplicationContext(write.context)
                Task { @MainActor [weak self] in
                    self?.recordWatchSyncSuccess(date)
                }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor [weak self] in
                    self?.recordWatchSyncFailure(message)
                }
            }
        }
    }

    /// Legacy compatibility hook for older callers. New Home code no longer
    /// publishes an automatic weekly coach plan to the Watch.
    func updateWatchTodayPlan(_ plan: WatchSync.TodayPlan) {
        cachedTodayPlan = plan
        guard let session = wcSession, session.isWatchAppInstalled else { return }
        var context = session.applicationContext
        context.merge(WatchSync.TodayPlan.contextDict(plan)) { _, new in new }
        enqueueWatchContextWrite(context, on: session, at: plan.updatedAt)
    }

    /// Removes the retired weekly Today-plan projection from the Watch's
    /// application context. This is idempotent and safe during migration from
    /// older builds that still sent an automatic coach plan.
    func clearWatchTodayPlan() {
        cachedTodayPlan = nil
        watchPayloadTask?.cancel()
        guard let session = wcSession, session.isWatchAppInstalled else { return }
        var context = session.applicationContext
        context.removeValue(forKey: WatchSync.Key.todayPlanSessions)
        context.removeValue(forKey: WatchSync.Key.todayPlanUpdatedAt)
        enqueueWatchContextWrite(context, on: session, at: Date())
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
        watchStartInProgress = true
        watchError = nil
        if !isUITestMode, WCSession.isSupported(), WCSession.default.activationState != .activated {
            pendingWatchStartType = rawType
            activateWCSession()
            return
        }
        performWatchStart(rawType: rawType, retryType: rawType, allowsRetry: true)
    }

    private func performWatchStart(rawType: String, retryType: String, allowsRetry: Bool) {
        watchStartInProgress = true
        guard watchAvailable, let session = wcSession else {
            watchStartInProgress = false
            watchError = "Apple Watch is unavailable — install Cladiron on your Apple Watch and try again"
            return
        }
        watchError = nil
        watchTimeout?.invalidate()

        let requestID = UUID()
        pendingWatchStart = PendingWatchStart(requestID: requestID, retryType: retryType,
                                              allowsRetry: allowsRetry)
        let command = WatchHRCommand(action: .start, requestID: requestID,
                                     workoutType: rawType, issuedAt: nextWatchHRCommandIssuedAt())
        // Durable, ordered copy first. When Cladiron isn't running on the
        // Watch, this is delivered as soon as the launch below brings it up,
        // and names the workout the launch started. The Watch treats the
        // immediate and queued copies as one command.
        session.transferUserInfo(command.payload)
        watchActive = false
        // Armed first so a launch that fails at once can cancel it.
        watchTimeout = Timer.scheduledTimer(
            withTimeInterval: 60,
            repeats: false,
            block: Self.watchTimeoutHandler(owner: self))
        if session.isReachable {
            watchHRRelay.begin(requestID: requestID)
            session.sendMessage(
                command.payload,
                replyHandler: Self.watchReplyHandler(owner: self, requestID: requestID),
                errorHandler: Self.watchErrorHandler(owner: self, requestID: requestID, rawType: rawType))
        } else {
            // Cladiron isn't running on the Watch. Open it rather than asking
            // the user to: HealthKit launches or wakes the Watch app and hands
            // it the workout, which it starts at once.
            watchHRRelay.begin(requestID: requestID, launchingWatchApp: true)
            launchWatchApp(rawType: rawType, requestID: requestID)
        }
    }

    nonisolated private static func watchReplyHandler(owner: AppModel, requestID: UUID) -> ([String: Any]) -> Void {
        { reply in
            let matchesRequest = (reply["requestID"] as? String).flatMap(UUID.init(uuidString:)) == requestID
            let accepted = reply["accepted"] as? Bool
            let reason = (reply["rejection"] as? String) ?? "unavailable"
            let rejection = WatchHRRejection(rawValue: reason)
            let activeRequestID = (reply["activeRequestID"] as? String).flatMap(UUID.init(uuidString:))
            Task { @MainActor [weak owner] in
                guard let owner, matchesRequest, let accepted else { return }
                owner.applyWatchStartReply(requestID: requestID, accepted: accepted,
                                           rejection: rejection, activeRequestID: activeRequestID)
            }
        }
    }

    /// Routes an answer to a start request. Only the first answer for the
    /// pending request acts; a duplicate acceptance just confirms.
    private func applyWatchStartReply(requestID: UUID, accepted: Bool,
                                      rejection: WatchHRRejection?, activeRequestID: UUID?) {
        guard requestID == watchHRRelay.activeRequestID else { return }
        guard let pending = pendingWatchStart, pending.requestID == requestID else {
            if accepted { watchHRRelay.acknowledged() }
            return
        }
        pendingWatchStart = nil
        if accepted { watchError = nil }
        handleWatchStartReply(accepted: accepted, rejection: rejection,
                              activeRequestID: activeRequestID,
                              retryType: pending.retryType, allowsRetry: pending.allowsRetry)
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
            watchStartInProgress = false
            watchTimeout?.invalidate(); watchTimeout = nil
            watchHRRelay.fail((rejection ?? .unavailable).userMessage)
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

    /// The immediate start message failed: the Watch app stopped being
    /// reachable (suspended, closed) between the check and the send. Open it
    /// instead; the queued copy of the command follows the launch.
    nonisolated private static func watchErrorHandler(owner: AppModel, requestID: UUID,
                                                      rawType: String) -> @Sendable (Error) -> Void {
        { _ in
            Task { @MainActor [weak owner] in
                owner?.watchStartMessageFailed(requestID: requestID, rawType: rawType)
            }
        }
    }

    private func watchStartMessageFailed(requestID: UUID, rawType: String) {
        guard watchHRRelay.activeRequestID == requestID,
              case .connecting = watchHRRelay.state else { return }
        watchHRRelay.begin(requestID: requestID, launchingWatchApp: true)
        launchWatchApp(rawType: rawType, requestID: requestID)
    }

    /// Opens Cladiron on the paired Watch with the workout
    /// (`CadenceWatchAppDelegate.handle(_:)` on the Watch starts it).
    private func launchWatchApp(rawType: String, requestID: UUID) {
        guard let provider = health as? HealthKitProvider else {
            watchAppLaunchFinished(requestID: requestID, launched: false, reason: nil)
            return
        }
        provider.startWatchApp(
            with: WatchWorkoutLaunch.configuration(forRawType: rawType),
            completion: Self.watchLaunchHandler(owner: self, requestID: requestID))
    }

    /// HealthKit calls this off the main thread; hop to the main actor.
    nonisolated private static func watchLaunchHandler(owner: AppModel,
                                                       requestID: UUID) -> @Sendable (Bool, (any Error)?) -> Void {
        { launched, error in
            let reason = error?.localizedDescription
            Task { @MainActor [weak owner] in
                owner?.watchAppLaunchFinished(requestID: requestID, launched: launched, reason: reason)
            }
        }
    }

    private func watchAppLaunchFinished(requestID: UUID, launched: Bool, reason: String?) {
        guard watchHRRelay.activeRequestID == requestID else { return }
        if launched {
            watchHRRelay.watchAppLaunched()
            return
        }
        // Withdraw the queued start so it can't begin a workout the next time
        // Cladiron opens on the Watch.
        stopWatchWorkout(targetRequestID: requestID)
        let detail = reason.map { " (\($0))" } ?? ""
        watchHRRelay.fail("Couldn’t open Cladiron on your Apple Watch\(detail). Check that it’s on your wrist and unlocked, then tap Check for Live HR.")
    }

    nonisolated private static func watchTimeoutHandler(owner: AppModel) -> @Sendable (Timer) -> Void {
        { _ in
            Task { @MainActor [weak owner] in
                guard let owner, owner.watchHRRelay.freshBPM == nil else { return }
                owner.watchHRRelay.timeout()
                owner.watchActive = false
                owner.watchStartInProgress = false
                owner.watchError = "No heart rate arrived from your Apple Watch. Check that it’s on your wrist and unlocked, then tap Check for Live HR."
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
        watchStartInProgress = false
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

    fileprivate func watchReachabilityChanged(reachable: Bool) {
        guard reachable, watchHRRelay.activeRequestID != nil else { return }
        // The Watch retries its latest sample after reachability returns. This
        // keeps a transient Apple Fitness/WatchConnectivity interruption from
        // becoming a permanent phone-side HR failure.
        watchError = nil
    }

    fileprivate func handleWatchMessage(_ message: [String: Any],
                                         replyHandler: (([String: Any]) -> Void)? = nil) {
        if let requestIDString = message["requestID"] as? String,
           let requestID = UUID(uuidString: requestIDString),
           let accepted = message["accepted"] as? Bool {
            // The Watch's answer to the queued copy of a start, sent as a
            // message. For a Watch app the phone launched it is the only
            // answer. The 60 s timeout keeps running until the first heart
            // rate, so an accepted start that never streams still reports.
            applyWatchStartReply(
                requestID: requestID,
                accepted: accepted,
                rejection: (message["rejection"] as? String).flatMap(WatchHRRejection.init(rawValue:)),
                activeRequestID: (message["activeRequestID"] as? String).flatMap(UUID.init(uuidString:)))
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
            if self.watchHRRelay.receive(bpm: Int(bpm), requestID: requestID) {
                self.watchTimeout?.invalidate(); self.watchTimeout = nil
                self.watchError = nil
                self.watchActive = true
                self.watchStartInProgress = false
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
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Import Watch cardio")
        defer {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
        }
        let ctx = ModelContext(container)
        do {
            let profile = CardioIntensityProfile.resolved(
                userEnteredMaximumHR: _settings?.cardioMaximumHROverride,
                age: _settings?.userAge)
            _ = try WorkoutRepository.ingest(completion, profile: profile, in: ctx)
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
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Import Watch strength")
        defer {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
        }
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

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak owner] in
            owner?.watchReachabilityChanged(reachable: reachable)
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
