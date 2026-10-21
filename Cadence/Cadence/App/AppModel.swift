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
            case .idle: return String(localized: "Not run yet")
            case .syncing: return String(localized: "Checking Apple Health…")
            case .completed(_, let insertedCount):
                return insertedCount == 0
                    ? String(localized: "Checked; no new workouts")
                    : String(localized: "Imported \(insertedCount) workouts")
            case .failed(let message): return String(localized: "Couldn’t check Apple Health: \(message)")
            }
        }
    }

    enum HealthRestoreStatus: Equatable, Sendable {
        case idle
        case restoring
        case completed(Date, HealthRestoreApplyReport)
        case failed(String)

        var isInProgress: Bool {
            if case .restoring = self { return true }
            return false
        }

        var detailText: String {
            switch self {
            case .idle: return String(localized: "Not run yet")
            case .restoring: return String(localized: "Restoring from Apple Health…")
            case .completed(_, let report):
                return String(localized: "Restored \(report.inserted + report.replaced) · \(report.summariesOnly) summary-only")
            case .failed(let message): return String(localized: "Restore paused: \(message)")
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
            case .idle: return String(localized: "No recent import")
            case .updating: return String(localized: "Updating private history…")
            case .completed: return String(localized: "Private history up to date")
            case .failed: return String(localized: "Update paused — open Diagnostics")
            }
        }
    }

    enum StoreMigrationStatus: Equatable, Sendable {
        case notNeeded
        case needsHealthAccess
        case migrating
        case readyToRestart
        case failed(String)

        var isInProgress: Bool {
            if case .migrating = self { return true }
            return false
        }
    }

    let health: HealthDataProviding
    let healthBackup: HealthBackupCoordinator
    /// The single paused-and-minimized cardio session (reopened from Today).
    let parkedCardio = ParkedCardioStore()
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
    /// Handshake state for the current phone-owned Watch-HR connection.
    private(set) var watchHRConnection = WatchHRConnection()
    @ObservationIgnored private var watchReconcileTimer: Timer?
    @ObservationIgnored private var lastWatchStartCommand: WatchHRCommand?
    @ObservationIgnored private let watchHRLog = Logger(subsystem: "guru.parso.cladiron", category: "watch-hr")
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
    /// Truthful Watch sync status. `upToDate` only follows a matching Watch acknowledgement;
    /// a local `updateApplicationContext` success is merely queued/awaiting.
    private(set) var watchSyncState: WatchSyncState = .activating
    /// Last time the Watch *confirmed* applying a snapshot (never a local write time).
    var lastWatchSyncAt: Date? { watchSyncTracker.lastConfirmedAt }
    /// Legacy pre-handshake "synced" timestamps were local writes; they migrate to unconfirmed.
    private let watchSyncTracker = WatchSyncTracker(
        store: UserDefaultsWatchSyncLedgerStore(),
        legacyLastSyncAt: UserDefaults.standard.object(forKey: "settings.lastWatchSyncAt") as? Date)
    @ObservationIgnored private var watchReconcileTask: Task<Void, Never>?
    private static let watchSyncLog = Logger(subsystem: "guru.parso.cladiron", category: "watch-sync")
    private let watchSessionDelegate: WatchSessionDelegateProxy
    private(set) var cloudKitAccountAvailability: CloudKitAccountAvailability = .checking
    private(set) var isRestoringCloudKitHistory = false
    private(set) var cloudKitImportStatus: CloudKitImportStatus = .idle
    private var cloudKitEventObserver: NSObjectProtocol?
    /// SwiftData's CloudKit exporter must not be kicked off by a Watch payload
    /// while the iPhone is backgrounded. Those writes used to outlive the
    /// WatchConnectivity callback and were the last app-owned work in the
    /// RUNNINGBOARD 0xdead10cc crash stack.
    private var applicationIsActive = false
    private static let pendingWatchImportKey = "watch.pendingImports.v1"
    /// CloudKit can deliver several import events while a new device is being
    /// hydrated. Keep Home in its lightweight placeholder state until the
    /// import burst has been quiet for a moment, then let it rebuild once.
    private var cloudKitImportQuietTask: Task<Void, Never>?

    /// Last time we ingested HealthKit workouts (FR-2.1), persisted across runs.
    var healthSyncStatus: HealthSyncStatus = .idle
    var healthRestoreStatus: HealthRestoreStatus = .idle
    var storeMigrationStatus: StoreMigrationStatus = .notNeeded
    /// Published while Home recomputes its ephemeral coach projection so the
    /// operation is visible in Settings → Transparency & Control without
    /// inserting transient content into the Home layout.
    var coachRefreshInProgress = false

    var lastHealthSync: Date? {
        get { (UserDefaults.standard.object(forKey: SettingsKey.lastHealthSync) as? Double).map { Date(timeIntervalSince1970: $0) } }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970, forKey: SettingsKey.lastHealthSync) }
    }

    /// Re-reads Cladiron-authored Health objects and applies the pure conflict
    /// policy to the local store. This is safe to repeat and intentionally does
    /// not report "no history" as an error because HealthKit can hide read data
    /// when its permission is disabled.
    func restoreHealthBackups() async {
        guard !healthRestoreStatus.isInProgress, let container = _modelContainer else { return }
        healthRestoreStatus = .restoring
        do {
            let incoming = await health.readHealthBackups(since: nil)
            let context = ModelContext(container)
            let local: [HealthRestoreLocalState] =
                (try context.fetch(FetchDescriptor<WorkoutSession>())).map {
                    HealthRestoreLocalState(kind: .strengthSession, id: $0.id,
                                            updatedAt: $0.updatedAt,
                                            healthObjectID: $0.healthKitWorkoutUUID,
                                            isDeleted: $0.deletedAt != nil)
                }
                + (try context.fetch(FetchDescriptor<CardioWorkout>())).map {
                    HealthRestoreLocalState(kind: .cardioWorkout, id: $0.id,
                                            updatedAt: $0.updatedAt,
                                            healthObjectID: $0.healthKitWorkoutUUID,
                                            isDeleted: $0.deletedAt != nil)
                }
                + (try context.fetch(FetchDescriptor<Assessment>())).map {
                    HealthRestoreLocalState(kind: .assessment, id: $0.id,
                                            updatedAt: $0.updatedAt)
                }
            let plan = HealthBackupRestorePlanner.plan(incoming: incoming, local: local)
            let report = try WorkoutRepository.applyHealthRestore(plan, in: context)
            healthRestoreStatus = .completed(Date(), report)
            if report.inserted > 0 || report.replaced > 0 {
                NotificationCenter.default.post(name: .workoutHistoryChanged, object: nil)
            }
        } catch {
            healthRestoreStatus = .failed(error.localizedDescription)
        }
    }

    var legacyStoreNeedsMigration: Bool {
        let directory = CadenceStore.applicationSupportDirectory()
        let legacyURL = CadenceStore.legacyStoreURL(in: directory)
        return FileManager.default.fileExists(atPath: legacyURL.path)
            && !CadenceStore.splitStoreReady(in: directory)
    }

    /// Runs the user-approved H5 migration. The old container remains active
    /// for this launch; the ready marker deliberately makes the split store
    /// selectable only on the next launch, after the HealthKit outbox is safe.
    func migrateLegacyStore() async {
        guard !isUITestMode, !storeMigrationStatus.isInProgress,
              legacyStoreNeedsMigration, let oldContainer = _modelContainer,
              let settings = _settings else {
            storeMigrationStatus = .notNeeded
            return
        }
        guard settings.autoSaveHealth else {
            storeMigrationStatus = .needsHealthAccess
            return
        }

        storeMigrationStatus = .migrating
        let directory = CadenceStore.applicationSupportDirectory()
        let legacyURL = CadenceStore.legacyStoreURL(in: directory)
        let urls = CadenceStore.splitStoreURLs(in: directory)
        let stateURL = directory.appendingPathComponent(StoreMigrationRuntime.stateFileName)
        let snapshotURL = directory.appendingPathComponent(StoreMigrationRuntime.snapshotFileName)
        do {
            guard await health.requestAuthorization() == .authorized else {
                storeMigrationStatus = .needsHealthAccess
                return
            }
            _ = try StoreMigrationRuntime.migrate(
                legacyURL: legacyURL, localURL: urls.local, syncURL: urls.sync,
                stateURL: stateURL, snapshotURL: snapshotURL, cloudKitEnabled: true)
            let context = ModelContext(oldContainer)
            _ = try await healthBackup.enqueueMigrationBackfill(from: context)
            try StoreMigrationRuntime.markHealthBackfillQueued(stateURL: stateURL)
            storeMigrationStatus = .readyToRestart
        } catch {
            storeMigrationStatus = .failed(error.localizedDescription)
        }
    }

    @MainActor
    override init() {
        let args = ProcessInfo.processInfo.arguments
        let uiTest = args.contains("-uiTest")
        self.isUITestMode = uiTest

        #if DEBUG
        let healthProvider: HealthDataProviding
        if uiTest {
            let fake = FakeHealthProvider()
            fake.authStatus = .authorized
            if let idx = args.firstIndex(of: "-todaySteps"), idx + 1 < args.count, let n = Int(args[idx + 1]) {
                fake.seededTodaySteps = n
            }
            if args.contains("-noHealthWorkouts") {
                fake.pendingWorkouts = []
            }
            healthProvider = fake
        } else {
            healthProvider = HealthKitProvider()
        }
        #else
        let healthProvider: HealthDataProviding = HealthKitProvider()
        #endif
        self.health = healthProvider
        self.healthBackup = HealthBackupCoordinator(health: healthProvider)

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
            return String(localized: "Opening Cladiron on your Apple Watch…")
        case .connecting:
            return String(localized: "Connecting to your Apple Watch…")
        case .waitingForSample:
            return String(localized: "Apple Watch connected · waiting for the first heart-rate reading…")
        case .live:
            return String(localized: "Live heart rate from Apple Watch")
        case .timedOut(let message), .failed(let message):
            return message
        case .unavailable(let reason):
            if watchStartInProgress { return String(localized: "Preparing the Apple Watch connection…") }
            return reason
        case .actionRequired(let message):
            if watchStartInProgress { return String(localized: "Preparing the Apple Watch connection…") }
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
    /// Watch request → phone strength session it was started for.
    private var watchRequestSessionIDs: [UUID: UUID] = [:]
    /// Legacy Watch Today-plan cache retained only for migration/tests. New
    /// builds do not populate it from the Home coach pipeline.
    private var cachedTodayPlan: WatchSync.TodayPlan?
    private var cachedWeekSummary: WatchSync.WeekSummary?
    /// Workouts the user chose to send to the Watch; mirrored in the application context.
    private var cachedSentWorkouts: [WatchSync.TodayPlan.Session] = []
    private var watchPayloadTask: Task<Void, Never>?

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
        drainPendingWatchImportsIfNeeded()
    }

    func setApplicationActive(_ active: Bool) {
        applicationIsActive = active
        if active {
            drainPendingWatchImportsIfNeeded()
            startWatchReconcileLoop()
        } else {
            watchReconcileTask?.cancel()
            watchReconcileTask = nil
        }
    }

    /// Foreground-only conservative cadence: a cheap local check every 30 s that only writes
    /// when the tracker's documented bounds allow it (confirmation older than 5 minutes, or an
    /// unacknowledged snapshot past its backoff). It also refreshes the time-derived status.
    private func startWatchReconcileLoop() {
        guard watchReconcileTask == nil else { return }
        watchReconcileTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { return }
                self.refreshWatchSyncState()
                self.pushSettingsContext(reason: .periodic)
            }
        }
    }

    private func refreshWatchSyncState() {
        let activated = wcSession?.activationState == .activated
        let state = watchSyncTracker.state(installed: watchAppInstalled, activated: activated)
        if state != watchSyncState { watchSyncState = state }
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
        CKContainer(identifier: CadenceStore.activeCloudKitContainerID()).accountStatus { [weak self] status, _ in
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

    /// Starts a (coalesced, acknowledged) settings reconciliation. `force` is the manual
    /// "Sync now": it always produces a fresh revision but never reports success itself.
    func pushSettingsContext(force: Bool = false, reason: WatchSyncTrigger = .contentChanged) {
        let trigger: WatchSyncTrigger = force && reason == .contentChanged ? .manual : reason
        guard let settings = _settings else {
            if force { watchSyncTracker.markSettingsUnavailable() }
            refreshWatchSyncState()
            return
        }
        guard let session = wcSession, session.isWatchAppInstalled else {
            // No Watch app: never write indefinitely.
            refreshWatchSyncState()
            return
        }
        guard watchSyncTracker.mayReconcile(trigger) else {
            Self.watchSyncLog.debug("coalesced trigger=\(trigger.rawValue, privacy: .public)")
            refreshWatchSyncState()
            return
        }
        let now = Date()
        let basePreferences = WatchSync.Preferences(
            unit: settings.unit,
            intervalColorBlind: settings.intervalColorBlind,
            restSeconds: settings.restSeconds,
            warmupMinutes: settings.warmupMinutes,
            cooldownMinutes: settings.cooldownMinutes,
            workoutSounds: settings.workoutSounds,
            spokenCues: settings.spokenCues,
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
                                                trigger: trigger, session: session)
            }
        }
    }

    private func finishWatchSettingsContext(basePreferences: WatchSync.Preferences,
                                            payload: WatchPayloadSnapshot,
                                            at date: Date,
                                            trigger: WatchSyncTrigger,
                                            session: WCSession) {
        var prefs = basePreferences
        prefs.recentPartnerNames = payload.recentPartnerNames
        var context = WatchSync.Preferences.contextDict(prefs, updatedAt: date)
        context[WatchSync.Key.customExercises] = payload.customExercises.map(\.propertyList)
        if let plan = cachedTodayPlan {
            context.merge(WatchSync.TodayPlan.contextDict(plan)) { _, new in new }
        } else {
            // A context is merged on the receiving side, so merely omitting the
            // keys would leave a stale plan visible on the Watch.
            context.removeValue(forKey: WatchSync.Key.todayPlanSessions)
            context.removeValue(forKey: WatchSync.Key.todayPlanUpdatedAt)
        }
        // The context is built fresh, so carry workouts sent to the Watch along with it.
        if !cachedSentWorkouts.isEmpty {
            context.merge(WatchSentWorkouts.contextDict(cachedSentWorkouts)) { _, new in new }
        }
        // The settings context is built fresh, so carry the This Week totals along with it.
        if let week = cachedWeekSummary {
            context.merge(WatchSync.WeekSummary.contextDict(week)) { _, new in new }
        }
        enqueueWatchContextWrite(context, on: session, at: date, trigger: trigger)
    }

    /// The single choke point for phone→Watch context writes. It stamps a versioned envelope
    /// (or coalesces the write away), then records the write as *queued only*; confirmation
    /// comes exclusively from the Watch's acknowledgement.
    private func enqueueWatchContextWrite(_ context: [String: Any],
                                          on session: WCSession,
                                          at date: Date,
                                          trigger: WatchSyncTrigger = .contentChanged) {
        var stamped = WatchSyncHandshake.Envelope.stripping(context)
        let components = WatchSyncHandshake.Components(context: stamped)
        guard let envelope = watchSyncTracker.prepare(components: components, trigger: trigger) else {
            Self.watchSyncLog.debug("coalesced unchanged trigger=\(trigger.rawValue, privacy: .public)")
            refreshWatchSyncState()
            return
        }
        stamped.merge(envelope.contextEntries) { _, new in new }
        Self.watchSyncLog.info("snapshot queued trigger=\(trigger.rawValue, privacy: .public)")
        refreshWatchSyncState()
        let revision = envelope.revision
        let write = WatchContextWrite(session: session, context: stamped)
        Self.watchContextQueue.async { [weak self] in
            do {
                try write.session.updateApplicationContext(write.context)
                Task { @MainActor [weak self] in
                    self?.watchSyncTracker.markWritten(revision: revision)
                    self?.refreshWatchSyncState()
                }
            } catch {
                Task { @MainActor [weak self] in
                    Self.watchSyncLog.error("context write failed")
                    self?.watchSyncTracker.markWriteFailed(revision: revision)
                    self?.refreshWatchSyncState()
                }
            }
        }
    }

    /// Publishes today's coach suggestion so the Watch Today hero matches the phone.
    func updateWatchTodayPlan(_ plan: WatchSync.TodayPlan) {
        cachedTodayPlan = plan
        guard let session = wcSession, session.isWatchAppInstalled else { return }
        var context = session.applicationContext
        context.merge(WatchSync.TodayPlan.contextDict(plan)) { _, new in new }
        enqueueWatchContextWrite(context, on: session, at: plan.updatedAt)
    }

    /// "Send Workout to Watch": queues a designed workout on the Watch as "Sent from your phone".
    /// Returns false when no paired Watch app is reachable for delivery, so the UI can say so.
    @discardableResult
    func sendWorkoutToWatch(_ workout: WatchSync.TodayPlan.Session) -> Bool {
        guard let session = wcSession, session.isWatchAppInstalled else { return false }
        var context = session.applicationContext
        if cachedSentWorkouts.isEmpty {
            cachedSentWorkouts = WatchSentWorkouts.sessions(from: context)
        }
        cachedSentWorkouts = WatchSentWorkouts.adding(workout, to: cachedSentWorkouts)
        context.merge(WatchSentWorkouts.contextDict(cachedSentWorkouts)) { _, new in new }
        enqueueWatchContextWrite(context, on: session, at: Date())
        return true
    }

    /// Publishes this week's sets and cardio minutes for the Watch's This Week page. It merges into
    /// the application context and is skipped when unchanged, so Home refreshes don't re-send it.
    func updateWatchWeekSummary(_ summary: WatchSync.WeekSummary) {
        cachedWeekSummary = summary
        guard let session = wcSession, session.isWatchAppInstalled else { return }
        var context = session.applicationContext
        if let current = WatchSync.WeekSummary.from(context: context),
           current.sets == summary.sets, current.setsMinimum == summary.setsMinimum,
           current.setsTarget == summary.setsTarget, current.cardioMinutes == summary.cardioMinutes {
            return
        }
        context.merge(WatchSync.WeekSummary.contextDict(summary)) { _, new in new }
        enqueueWatchContextWrite(context, on: session, at: summary.updatedAt)
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
            watchError = String(localized: "Apple Watch is unavailable — install Cladiron on your Apple Watch and try again")
            return
        }
        watchError = nil
        watchTimeout?.invalidate()

        let requestID = UUID()
        // Bind this request to the concrete phone session now, so a delayed
        // message from workout A can never land in workout B.
        let phoneSessionID = _active?.strengthSession?.id
        if let phoneSessionID {
            watchRequestSessionIDs[requestID] = phoneSessionID
            WatchHeartRateRouteStore().add(sessionID: phoneSessionID, requestID: requestID)
        }
        pendingWatchStart = PendingWatchStart(requestID: requestID, retryType: retryType,
                                              allowsRetry: allowsRetry)
        let command = WatchHRCommand(action: .start, requestID: requestID,
                                     workoutType: rawType, issuedAt: nextWatchHRCommandIssuedAt(),
                                     phoneWorkoutSessionID: phoneSessionID)
        // Durable, ordered copy first. When Cladiron isn't running on the
        // Watch, this is delivered as soon as the launch below brings it up,
        // and names the workout the launch started. The Watch treats the
        // immediate and queued copies as one command.
        lastWatchStartCommand = command
        if let phoneSessionID {
            watchHRConnection.start(.init(phoneSessionID: phoneSessionID, requestID: requestID), now: Date())
            watchHRLog.info("command queued state=\(self.watchHRConnection.state.label, privacy: .public)")
            scheduleWatchReconcile()
        }
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
        { [weak owner] reply in
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
        if accepted, let sessionID = watchRequestSessionIDs[requestID],
           watchHRConnection.adopted(.init(phoneSessionID: sessionID, requestID: requestID)) {
            watchHRLog.info("adoption accepted")
        }
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
        { [weak owner] _ in
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
        { [weak owner] launched, error in
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
        watchHRRelay.fail(String(localized: "Couldn’t open Cladiron on your Apple Watch\(detail). Check that it’s on your wrist and unlocked, then tap Check for Live HR."))
    }

    nonisolated private static func watchTimeoutHandler(owner: AppModel) -> @Sendable (Timer) -> Void {
        { [weak owner] _ in
            Task { @MainActor [weak owner] in
                guard let owner, owner.watchHRRelay.freshBPM == nil else { return }
                owner.watchHRRelay.timeout()
                owner.watchActive = false
                owner.watchStartInProgress = false
                owner.watchError = String(localized: "No heart rate arrived from your Apple Watch. Check that it’s on your wrist and unlocked, then tap Check for Live HR.")
                owner.watchTimeout?.invalidate()
            }
        }
    }

    // MARK: - Watch HR reconciliation

    /// Plain-language state for the live-workout HR row.
    var watchHRStatusText: String {
        switch watchHRConnection.state {
        case .notRequested, .ended, .ending: return String(localized: "Apple Watch HR is not connected")
        case .startingWatchWorkout: return String(localized: "Connecting to Watch")
        case .awaitingWatchAdoption, .awaitingFirstSample: return String(localized: "Watch workout started—waiting for HR")
        case .live: return watchHRConnection.isLive(now: Date())
            ? String(localized: "Receiving live HR") : String(localized: "Connection needs attention")
        case .reconciling: return String(localized: "Reconnecting")
        case .recoverableFailure(.watchOnlyWorkoutActive, _):
            return String(localized: "A workout is already running on your Apple Watch. End it there, then tap Reconnect Apple Watch HR.")
        case .recoverableFailure: return String(localized: "Connection needs attention")
        }
    }

    /// The "Reconnect Apple Watch HR" action: runs the scoped protocol; it
    /// never starts a second Watch workout.
    func reconnectWatchHR() {
        guard let reason = watchHRConnection.userReconnect(now: Date()) else { return }
        sendWatchStateQuery(reason)
        scheduleWatchReconcile()
    }

    private func requestWatchReconcile(_ reason: WatchHRReconcileReason) {
        guard let reason = watchHRConnection.reachabilityOrActivation(reason, now: Date()) else { return }
        sendWatchStateQuery(reason)
        scheduleWatchReconcile()
    }

    /// One-shot timer for the next bounded attempt; no continuous polling.
    private func scheduleWatchReconcile() {
        watchReconcileTimer?.invalidate()
        watchReconcileTimer = Timer.scheduledTimer(withTimeInterval: WatchHRConnection.initialWait, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let reason = self.watchHRConnection.tick(now: Date()) {
                    self.sendWatchStateQuery(reason)
                    self.scheduleWatchReconcile()
                } else if case .reconciling = self.watchHRConnection.state {
                    self.scheduleWatchReconcile()
                }
            }
        }
    }

    private func sendWatchStateQuery(_ reason: WatchHRReconcileReason) {
        guard let identity = watchHRConnection.identity, let session = wcSession else { return }
        watchHRLog.info("state query reason=\(reason.rawValue, privacy: .public) attempt=\(self.watchHRConnection.attempts)")
        guard session.isReachable else {
            // Guaranteed delivery: redeliver the idempotent start; the Watch
            // treats a repeat of an adopted command as the same command.
            redeliverWatchStart()
            return
        }
        let query = WatchHRCommand(action: .query, requestID: identity.requestID,
                                   issuedAt: nextWatchHRCommandIssuedAt())
        session.sendMessage(query.payload, replyHandler: { [weak self] reply in
            let box = UncheckedWatchUserInfo(value: reply)
            Task { @MainActor [weak self] in self?.applyWatchStateReply(box.value, identity: identity) }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor [weak self] in self?.redeliverWatchStart() }
        })
    }

    private func redeliverWatchStart() {
        guard let command = lastWatchStartCommand, command.requestID == watchHRConnection.identity?.requestID else { return }
        wcSession?.transferUserInfo(command.payload)
        if wcSession?.isReachable == true { wcSession?.sendMessage(command.payload, replyHandler: nil, errorHandler: nil) }
    }

    private func applyWatchStateReply(_ reply: [String: Any], identity: WatchHRConnectionIdentity) {
        guard identity == watchHRConnection.identity, let report = WatchHRStateReport(payload: reply) else { return }
        let decision = WatchHRConnection.decide(report: report, expecting: identity)
        watchHRLog.info("reconcile decision applied")
        watchHRConnection.apply(decision)
        switch decision {
        case .accept:
            watchHRRelay.acknowledged()
        case .redeliverStart:
            redeliverWatchStart()
        case .stopOrphan(let orphan):
            // Only ever a phone-owned session (it carries a request ID); a
            // Watch-only workout reports no ID and is a conflict instead.
            let stop = WatchHRCommand(action: .stop, requestID: orphan, issuedAt: nextWatchHRCommandIssuedAt())
            wcSession?.sendMessage(stop.payload, replyHandler: nil, errorHandler: nil)
            wcSession?.transferUserInfo(stop.payload)
            redeliverWatchStart()
        case .conflict:
            watchError = watchHRStatusText
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
        watchReconcileTimer?.invalidate(); watchReconcileTimer = nil
        if watchHRConnection.identity?.requestID == targetRequestID { watchHRConnection.end() }
        watchHRRelay.cancel()
        if recordsWatchStop {
            watchStopCount += 1
            UserDefaults.standard.set(watchStopCount, forKey: "uitest.watchStopCount")
        }
        watchActive = false
        watchStartInProgress = false
        watchError = nil
        hrm.clearExternalBPM()
        guard let targetRequestID, let session = wcSession else { return }
        requestWatchHeartRateFinalization(requestID: targetRequestID)
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

    // MARK: - Durable Watch heart rate

    @ObservationIgnored private var _watchHeartRateReceiver: WatchHeartRateReceiver?
    private var watchHeartRateReceiver: WatchHeartRateReceiver {
        if let existing = _watchHeartRateReceiver { return existing }
        let receiver = makeWatchHeartRateReceiver()
        _watchHeartRateReceiver = receiver
        return receiver
    }

    private func makeWatchHeartRateReceiver() -> WatchHeartRateReceiver {
        WatchHeartRateReceiver(
        store: WatchHeartRateReceiptDefaultsStore(),
        transport: PhoneWCHeartRateTransport(),
        expectedRequestID: { WatchHeartRateRouteStore().requestID(for: $0) },
        persist: { [weak self] sessionID, observations in
            self?.persistWatchObservations(observations, sessionID: sessionID) ?? false
        })
    }

    /// Handles a versioned Watch HR protocol message. Returns the legacy
    /// `ack` flag; the protocol acknowledgement itself is sent by the receiver
    /// only after persistence succeeds.
    @discardableResult
    private func handleWatchHeartRateProtocol(_ message: [String: Any]) -> Bool {
        switch watchHeartRateReceiver.handle(message) {
        case .accepted, .duplicate, .finalizationUpdated: return true
        case .rejected, .persistenceFailed: return false
        }
    }

    /// Writes observations through the session-owned recorder: the live one for
    /// the active workout, otherwise one bound to the retained finished session.
    private func persistWatchObservations(_ observations: [WatchHRObservation], sessionID: UUID) -> Bool {
        let make = { (source: HeartRateObservationSource, o: WatchHRObservation) in
            HeartRateObservation(source: source, observedAt: Date(timeIntervalSince1970: o.sampleEnd),
                                 bpm: o.bpm, sampleID: o.sampleID)
        }
        if let active = _active, let session = active.strengthSession, session.id == sessionID,
           let recorder = active.heartRateRecorder, recorder.sessionID == sessionID {
            for o in observations { recorder.record(make(o.source, o)) }
            return recorder.flush()
        }
        guard let container = _modelContainer else { return false }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })
        guard let session = try? context.fetch(descriptor).first else { return false }
        let recorder = PhoneStrengthHeartRateRecorder(session: session, save: { try context.save() })
        for o in observations { recorder.record(make(o.source, o)) }
        guard session.endedAt != nil else { return recorder.flush() }
        let profile = CardioIntensityProfile.resolved(
            userEnteredMaximumHR: _settings?.cardioMaximumHROverride, age: _settings?.userAge)
        let saved = recorder.finalize(profile: profile)
        if saved { NotificationCenter.default.post(name: .workoutHistoryChanged, object: nil) }
        return saved
    }

    /// Normal Finish: ask the Watch to flush instead of discarding. The route
    /// stays retained so a late batch merges into this exact session.
    private func requestWatchHeartRateFinalization(requestID: UUID) {
        let routes = WatchHeartRateRouteStore()
        guard let sessionID = routes.sessionID(for: requestID) else { return }
        routes.markFinalizationRequested(sessionID: sessionID)
        watchHeartRateReceiver.requestFinalization(sessionID: sessionID, watchRequestID: requestID)
    }

    /// True while a finished workout still awaits the Watch's final heart-rate
    /// batches (`watchHRFinalizationPending`); its identifiers are retained.
    func watchHRFinalizationPending(sessionID: UUID) -> Bool {
        guard let route = WatchHeartRateRouteStore().routes.first(where: { $0.sessionID == sessionID }) else { return false }
        return route.finalizationRequested && !watchHeartRateReceiver.isFinalizationComplete(sessionID: sessionID)
    }

    /// Explicit, user-confirmed discard of a workout's retained Watch HR state.
    func discardWatchHeartRate(sessionID: UUID) {
        watchHeartRateReceiver.discard(sessionID: sessionID)
        WatchHeartRateRouteStore().remove(sessionID: sessionID)
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
}

// MARK: - Main-actor WatchConnectivity handlers

extension AppModel {
    fileprivate func watchActivationCompleted(installed: Bool) {
        watchAppInstalled = installed
        refreshWatchSyncState()
        pushSettingsContext(reason: .activation)
        if installed, let rawType = pendingWatchStartType {
            pendingWatchStartType = nil
            performWatchStart(rawType: rawType, retryType: rawType, allowsRetry: true)
        }
    }

    /// The Watch asked for a snapshot (it saw missing/stale context): reconcile without user action.
    private func handleWatchSyncRequest(_ message: [String: Any]) {
        let outcome = watchSyncTracker.receiveWatchRequest(
            appliedRevision: message[WatchSyncHandshake.Key.appliedRevision] as? Int,
            protocolVersion: message[WatchSyncHandshake.Key.protocolVersion] as? Int)
        Self.watchSyncLog.info("watch request outcome=\(String(describing: outcome), privacy: .public)")
        refreshWatchSyncState()
        // An incompatible Watch keeps its current state; still offer the latest snapshot.
        pushSettingsContext(reason: .watchRequest)
    }

    /// Only a matching, valid acknowledgement confirms a snapshot.
    private func handleWatchSyncAck(_ ack: WatchSyncHandshake.Ack) {
        let outcome = watchSyncTracker.receive(ack: ack)
        Self.watchSyncLog.info("ack outcome=\(String(describing: outcome), privacy: .public)")
        refreshWatchSyncState()
        switch outcome {
        case .watchAhead, .watchBehind:
            pushSettingsContext(reason: .watchRequest)
        default:
            break
        }
    }

    fileprivate func watchStateChanged(installed: Bool) {
        let becameInstalled = installed && !watchAppInstalled
        watchAppInstalled = installed
        // Anything published while the Watch app was missing was dropped, so resend settings, the
        // Today plan and the This Week totals once it appears.
        refreshWatchSyncState()
        if becameInstalled { pushSettingsContext(reason: .installed) }
    }

    fileprivate func watchReachabilityChanged(reachable: Bool) {
        if reachable { pushSettingsContext(reason: .reachability) }
        if reachable {
            for route in WatchHeartRateRouteStore().routes where route.finalizationRequested
                && !watchHeartRateReceiver.isFinalizationComplete(sessionID: route.sessionID) {
                watchHeartRateReceiver.requestFinalization(sessionID: route.sessionID, watchRequestID: route.requestID)
            }
        }
        guard reachable, watchHRRelay.activeRequestID != nil else { return }
        watchHRLog.info("reachability restored")
        requestWatchReconcile(.reachabilityChanged)
        // The Watch retries its latest sample after reachability returns. This
        // keeps a transient Apple Fitness/WatchConnectivity interruption from
        // becoming a permanent phone-side HR failure.
        watchError = nil
    }

    fileprivate func handleWatchMessage(_ message: [String: Any],
                                         replyHandler: (([String: Any]) -> Void)? = nil) {
        if WatchHRMessage.isWatchHRPayload(message) {
            replyHandler?(["ack": handleWatchHeartRateProtocol(message)])
            return
        }
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
            guard applicationIsActive else {
                enqueuePendingWatchImport(message)
                replyHandler?(["ack": false])
                return
            }
            let accepted = handleWatchCardioCompletion(message)
            replyHandler?(accepted ? completionAck(for: message) : ["ack": false])
            return
        }
        if message[WatchSync.Key.command] as? String == WatchSync.Key.transcribeQuickTalk {
            // Watch Quick Talk (D-W2): transcribe the clip here and reply; the clip is deleted.
            guard let audio = message[WatchSync.Key.quickTalkAudio] as? Data else {
                replyHandler?([WatchSync.Key.quickTalkError: "noAudio"])
                return
            }
            let ext = message[WatchSync.Key.quickTalkFileExtension] as? String ?? "m4a"
            Task { @MainActor in
                let reply = await QuickTalkClipTranscriber.transcribe(audio, fileExtension: ext)
                replyHandler?(reply)
            }
            return
        }
        if message[WatchSync.Key.command] as? String == WatchSync.Key.requestSettingsSync {
            handleWatchSyncRequest(message)
            replyHandler?(["ack": true])
            return
        }
        if let ack = WatchSyncHandshake.Ack(message: message) {
            handleWatchSyncAck(ack)
            replyHandler?(["ack": true])
            return
        }

        guard let bpm = message["bpm"] as? Double,
              let requestIDString = message["requestID"] as? String,
              let requestID = UUID(uuidString: requestIDString) else {
            replyHandler?(["ack": false])
            return
        }
        if let rejection = watchHRRelay.sampleRejection(requestID: requestID) {
            // Explicit negative status, never `ack: true`, so the Watch and the
            // user can see the sample was not applied.
            watchHRLog.notice("sample rejected reason=\(rejection, privacy: .public)")
            if rejection == "requestMismatch" { _ = watchHRConnection.receiveSample(requestID: requestID, at: Date()) }
            replyHandler?(["ack": false, "rejection": rejection])
            if rejection == "requestMismatch" { requestWatchReconcile(.requestMismatch) }
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.watchHRRelay.receive(bpm: Int(bpm), requestID: requestID) {
                _ = self.watchHRConnection.receiveSample(requestID: requestID, at: Date())
                self.watchTimeout?.invalidate(); self.watchTimeout = nil
                self.watchError = nil
                self.watchActive = true
                self.watchStartInProgress = false
                self.hrm.injectExternalBPM(bpm)
                self.recordWatchObservation(message, bpm: bpm, requestID: requestID)
            }
        }
        replyHandler?(["ack": true])
    }

    /// Captures a real, timestamped Watch reading into the active session's
    /// durable recorder. Packets without a measurement timestamp (display
    /// heartbeats from older Watch builds) are never recorded; a resent
    /// heartbeat reuses its `sampleEnd` and deduplicates.
    private func recordWatchObservation(_ message: [String: Any], bpm: Double, requestID: UUID) {
        guard let end = message["sampleEnd"] as? TimeInterval,
              let session = _active?.strengthSession,
              watchRequestSessionIDs[requestID] == session.id,
              let recorder = _active?.heartRateRecorder, recorder.sessionID == session.id else { return }
        let sampleID = (message["sampleID"] as? String)
        let source: HeartRateObservationSource = (message["source"] as? String)
            .flatMap(HeartRateObservationSource.init(rawValue:)) ?? .watchHealthKit
        recorder.record(HeartRateObservation(
            source: source, observedAt: Date(timeIntervalSince1970: end), bpm: bpm,
            requestID: requestID, sampleID: sampleID))
    }

    fileprivate func handleWatchUserInfo(_ userInfo: [String: Any]) {
        if WatchHRMessage.isWatchHRPayload(userInfo) {
            handleWatchHeartRateProtocol(userInfo)
            return
        }
        if let ack = WatchSyncHandshake.Ack(message: userInfo) {
            handleWatchSyncAck(ack)
            return
        }
        if userInfo[WatchSync.Key.command] as? String == WatchSync.Key.requestSettingsSync {
            handleWatchSyncRequest(userInfo)
            return
        }
        guard let action = userInfo["action"] as? String else { return }
        guard ["cardio_completion", "log_set", "end_session", "discard_session",
               "delete_exercise", "delete_set", "set_unit", "set_distance_unit"]
                .contains(action) else { return }
        guard applicationIsActive else {
            enqueuePendingWatchImport(userInfo)
            return
        }
        if !processWatchUserInfo(userInfo) {
            enqueuePendingWatchImport(userInfo)
        }
    }

    @discardableResult
    private func handleWatchCardioCompletion(_ info: [String: Any]) -> Bool {
        guard let data = info["payload"] as? Data,
              let completion = try? WatchCardioCompletion.decode(data),
              let container = _modelContainer else { return false }
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

    @discardableResult
    private func handleWatchStrengthMutation(_ info: [String: Any]) -> Bool {
        guard let container = _modelContainer else { return false }
        let ctx = ModelContext(container)
        do {
            let action = try WatchStrengthSyncApplier.apply(
                userInfo: info,
                in: ctx,
                phoneActiveID: _active?.strengthSession?.id,
                intensityProfile: _settings.map {
                    CardioIntensityProfile.resolved(userEnteredMaximumHR: $0.cardioMaximumHROverride,
                                                    age: $0.userAge, updatedAt: Date())
                }
            )
            guard action != .ignored else { return true }
            switch action {
            case .logSet:
                NotificationCenter.default.post(name: .watchSetLogged, object: nil)
            case .endSession:
                NotificationCenter.default.post(name: .watchSessionEnded, object: nil)
            default:
                break
            }
            NotificationCenter.default.post(name: .workoutHistoryChanged, object: nil)
            return true
        } catch {
            return false
        }
    }

    private func processWatchUserInfo(_ info: [String: Any]) -> Bool {
        guard let action = info["action"] as? String else { return true }
        switch action {
        case "cardio_completion":
            return handleWatchCardioCompletion(info)
        case "log_set", "end_session", "discard_session", "delete_exercise", "delete_set":
            return handleWatchStrengthMutation(info)
        case "set_unit":
            handleWatchSetUnit(info)
            return true
        case "set_distance_unit":
            handleWatchSetDistanceUnit(info)
            return true
        default:
            return true
        }
    }

    private func enqueuePendingWatchImport(_ info: [String: Any]) {
        guard PropertyListSerialization.propertyList(info, isValidFor: .binary) else { return }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: info,
                                                              format: .binary,
                                                              options: 0) else { return }
        var pending = UserDefaults.standard.array(forKey: Self.pendingWatchImportKey) as? [Data] ?? []
        pending.append(data)
        UserDefaults.standard.set(pending, forKey: Self.pendingWatchImportKey)
    }

    private func drainPendingWatchImportsIfNeeded() {
        guard applicationIsActive, _modelContainer != nil else { return }
        var pending = UserDefaults.standard.array(forKey: Self.pendingWatchImportKey) as? [Data] ?? []
        while let data = pending.first,
              let info = try? PropertyListSerialization.propertyList(from: data,
                                                                       options: [],
                                                                       format: nil) as? [String: Any] {
            guard processWatchUserInfo(info) else { break }
            pending.removeFirst()
        }
        UserDefaults.standard.set(pending, forKey: Self.pendingWatchImportKey)
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
