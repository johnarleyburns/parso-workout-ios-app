import Foundation
import HealthKit
import WatchConnectivity
import WatchKit
import CadenceCore
import CadenceFeatures

@Observable
@MainActor
final class WatchWorkoutManager: NSObject {

    // Updated by the dedicated heart-rate polling extension as well as the
    // manager's HealthKit/Bluetooth paths.
    var currentBPM: Double?
    var isActive: Bool = false
    var isMonitoring: Bool = false
    var workoutType: String?

    var hrSource: HRSource {
        get { HRSource(rawValue: hrSourceRaw) ?? .appleWatch }
        set { hrSourceRaw = newValue.rawValue }
    }

    // Written only by WatchWorkoutManager+HealthAuthorization.
    var hrAuthorized: Bool = false
    var workoutShareAuthorized: Bool = false
    /// Whether the first-screen Heart Rate Access boundary is showing. Driven by
    /// HealthKit's request status; see `WatchHealthAuthorizationGate`.
    var healthAuthorizationGateActive: Bool
    var healthPromptDismissedThisLaunch = false
    var healthAuthorizationFlowStarted = false
    /// WatchConnectivity activation and workout recovery run once per process,
    /// even if the boundary reappears after HealthKit answers.
    @ObservationIgnored var launchSyncStarted = false
    private(set) var bleState: BLEConnectionState? = nil
    private(set) var bleBattery: Int? = nil

    private(set) var elapsed: TimeInterval = 0
    private(set) var avgHeartRate: Double?
    private(set) var maxHeartRate: Double?
    private(set) var distanceMeters: Double = 0
    var heartRateEnabled: Bool = true
    var gpsEnabled: Bool = false
    var savedSummary: SavedWorkoutSummary?
    var currentHRSamplesForSummary: [HRSamplePoint] { recordedHRSamples }
    var phoneSyncState: WatchSync.Status = .idle
    var lastPhoneSyncAt: Date? = UserDefaults.standard.object(forKey: "watch.lastPhoneSyncAt") as? Date
    var lastPhoneSyncError: String?
    var todayPlan: WatchSync.TodayPlan?
    var recentPartnerNames: [String] = []
    var pendingCustomExercises: [WatchSync.CustomExercise] = []
    var customExercisesUpdatedAt = Date.distantPast
    /// Background custom-exercise writes run one at a time, so two quick
    /// replays of a new list can't both insert the same exercise.
    @ObservationIgnored var customExerciseApplyTask: Task<Void, Never>?
    @ObservationIgnored var customExerciseApplyingFingerprint: String?
    var pendingCardioCompletions: [WatchCardioCompletion] = []
    struct SavedWorkoutSummary {
        let duration: TimeInterval, avgHR: Double?, maxHR: Double?, distanceMeters: Double
        let hrSamples: [HRSamplePoint]
        init(duration: TimeInterval, avgHR: Double?, maxHR: Double?, distanceMeters: Double,
             hrSamples: [HRSamplePoint] = []) {
            self.duration = duration; self.avgHR = avgHR; self.maxHR = maxHR
            self.distanceMeters = distanceMeters; self.hrSamples = hrSamples
        }
    }
    private var hrSourceRaw: String {
        get { UserDefaults.standard.string(forKey: "watch.hrSource") ?? HRSource.appleWatch.rawValue }
        set { UserDefaults.standard.set(newValue, forKey: "watch.hrSource") }
    }
    let store = HKHealthStore()
    var session: HKWorkoutSession?
    var builder: HKLiveWorkoutBuilder?
    // Internal so the dedicated polling extension can own timer lifecycle.
    @ObservationIgnored var hrPollTimer: Timer?
    /// The single pending heart-rate relay timer (a delayed reading or the
    /// next heartbeat); see WatchWorkoutManager+HeartRatePolling.
    @ObservationIgnored var relayTimer: Timer?
    /// Bumped by every start and stop, so a stale authorization can't begin a session.
    @ObservationIgnored var startGeneration = 0
    @ObservationIgnored var relaySchedule = WatchHRRelaySchedule()
    /// Whether the app is active (screen on, in front); gates the 1 s display refresh.
    @ObservationIgnored var displayActive = true
    /// Set while a phone-launched workout waits for the phone's command to name it.
    @ObservationIgnored var phoneLaunchPendingSince: Date?
    @ObservationIgnored var recoveryInFlight = false
    private var ble: WatchHeartRateBLE?
    var sessionStart: Date?
    var phoneRequestID: String?
    private var accumulatedHR: Double = 0
    private var hrCount: Int = 0
    private var recordedHRSamples: [HRSamplePoint] = []
    private var elapsedTracker = ElapsedTimeTracker()
    enum PersistedWorkoutKey {
        static let active = "watch.activeWorkout.active"
        static let type = "watch.activeWorkout.type"
        static let monitoring = "watch.activeWorkout.monitoring"
        static let phoneRequestID = "watch.activeWorkout.phoneRequestID"
    }
    var watchAppSettings: AppSettings? {
        didSet {
            if let pendingApplicationContext {
                applySettingsContext(pendingApplicationContext)
                self.pendingApplicationContext = nil
            }
        }
    }
    var pendingApplicationContext: [String: Any]?

    let uiTestMode: Bool

    init(uiTestMode: Bool = false) {
        self.uiTestMode = uiTestMode
        self.healthAuthorizationGateActive = WatchHealthAuthorizationGate.initialGateActive()
        super.init()
        pendingCardioCompletions = Self.loadPendingCardioCompletions()
    }

    var wcSession: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func activateWCSession() {
        guard let session = wcSession else { return }
        session.delegate = self
        session.activate()
        flushPendingCardioCompletions()
    }

    @discardableResult
    func startWorkout(type rawType: String, cardioType: CardioType? = nil,
                      spec: WorkoutConfigurationSpec? = nil, phoneRequestID: UUID? = nil) -> Bool {
        guard !isActive, !isMonitoring else { return false }
        // Only `startPhoneLaunchedWorkout` marks a start as awaiting the phone.
        phoneLaunchPendingSince = nil
        let resolvedSpec = spec ?? WorkoutConfigurationSpec(for: rawType)
        self.phoneRequestID = phoneRequestID?.uuidString
        heartRateEnabled = resolvedSpec.heartRateEnabled
        gpsEnabled = resolvedSpec.usesGPS
        workoutType = rawType
        isActive = true; isMonitoring = false
        persistWorkoutMetadata(type: rawType, monitoring: false)
        let activity = Self.activityType(for: rawType)
        if uiTestMode { sessionStart = Date(); beginSession(activity: activity, spec: resolvedSpec); return true }
        startGeneration &+= 1
        let generation = startGeneration
        Task {
            let authorized = await requestWorkoutAuthorization()
            // A stop (or a newer start) while authorization was pending owns
            // the state now; beginning here would leave an untracked session.
            guard generation == startGeneration, isActive else { return }
            guard authorized else {
                isActive = false; self.phoneRequestID = nil
                clearPersistedWorkoutMetadata()
                return
            }
            beginSession(activity: activity, spec: resolvedSpec)
        }
        return true
    }
    func startMonitoringSession() {
        guard !isActive, !isMonitoring else { return }
        phoneRequestID = nil
        phoneLaunchPendingSince = nil
        isMonitoring = true; workoutType = "monitoring"
        persistWorkoutMetadata(type: "monitoring", monitoring: true)
        if uiTestMode { sessionStart = Date(); beginSession(activity: .other); return }
        startGeneration &+= 1
        let generation = startGeneration
        Task {
            let authorized = await requestWorkoutAuthorization()
            guard generation == startGeneration, isMonitoring else { return }
            guard authorized else {
                isMonitoring = false
                clearPersistedWorkoutMetadata()
                return
            }
            beginSession(activity: .other)
        }
    }

    func stopMonitoringSession() {
        guard isMonitoring else { return }
        stopWorkout(save: false)
    }
    func stopWorkout(save: Bool = true) {
        guard isActive || isMonitoring else {
            phoneRequestID = nil
            clearPersistedWorkoutMetadata()
            return
        }
        clearPersistedWorkoutMetadata()
        if save {
            elapsed = effectiveElapsed
            let avg: Double? = hrCount > 0 ? (accumulatedHR / Double(hrCount)) : nil
            savedSummary = SavedWorkoutSummary(duration: elapsed, avgHR: avg, maxHR: maxHeartRate,
                                               distanceMeters: distanceMeters, hrSamples: recordedHRSamples)
        }
        let b = builder; let s = session
        hrPollTimer?.invalidate(); hrPollTimer = nil
        stopHeartRateRelay()
        phoneLaunchPendingSince = nil
        startGeneration &+= 1
        builder = nil; session = nil
        ble?.disconnect(); ble = nil; currentBPM = nil
        isActive = false; isMonitoring = false; workoutType = nil; bleState = nil
        phoneRequestID = nil
        sessionStart = nil; accumulatedHR = 0; hrCount = 0
        recordedHRSamples = []
        isSwimSession = false; isOutdoorSession = false
        heartRateEnabled = true; gpsEnabled = false
        autoPauseDetector.reset(); lastAutoPauseDistance = 0
        elapsed = 0; avgHeartRate = nil; maxHeartRate = nil; distanceMeters = 0
        elapsedTracker.reset()
        if let b, let s {
            b.endCollection(withEnd: Date()) { _, _ in save ? b.finishWorkout(completion: {_,_ in}) : b.discardWorkout() }
            s.end()
        }
    }

    func liveSummary() -> (duration: TimeInterval, avgHR: Double?, maxHR: Double?, distanceMeters: Double) {
        elapsed = effectiveElapsed
        let avg: Double? = hrCount > 0 ? (accumulatedHR / Double(hrCount)) : nil
        return (elapsed, avg, maxHeartRate, distanceMeters)
    }

    func resetSavedSummary() { savedSummary = nil }
    private var lastAutoPauseDistance: Double = 0
    private func evaluateAutoPause(distance m: Double) {
        guard isOutdoorSession else { return }
        let speed: Double? = (m - lastAutoPauseDistance) > 0 ? (m - lastAutoPauseDistance) : nil
        lastAutoPauseDistance = m
        let enabled = UserDefaults.standard.object(forKey: "watch.cardio.autoPause") as? Bool ?? true
        switch autoPauseDetector.evaluate(speedMPS: speed, isDisabled: !enabled) {
        case .pause: if session?.state == .running { session?.pause(); WKInterfaceDevice.current().play(.notification) }
        case .resume: if session?.state == .paused { session?.resume() }
        case .none: break
        }
    }

    func switchToSource(_ source: HRSource) {
        hrSource = source
        guard isActive || isMonitoring else { return }
        if source == .appleWatch { ble?.disconnect(); ble = nil; bleState = nil }
        else { startBLE() }
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
                    self.accumulatedHR += value
                    self.hrCount += 1
                    self.recordedHRSamples.append(HRSamplePoint(t: self.effectiveElapsed, bpm: value))
                    if self.maxHeartRate == nil || value > (self.maxHeartRate ?? 0) {
                        self.maxHeartRate = value
                    }
                    self.relayReading(value, endingAt: nil)
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

    var autoPauseDetector = AutoPauseDetector()
    var manualLapCount: Int = 0
    var autoLapCount: Int = 0
    var isSwimSession: Bool = false
    var isOutdoorSession: Bool = false

    func incrementManualLap() { manualLapCount += 1 }
    func enableWaterLock() { WKInterfaceDevice.current().enableWaterLock() }
    func togglePause() {
        guard let s = session else { return }
        if s.state == .running { s.pause(); elapsedTracker.startPause() }
        else if s.state == .paused { s.resume(); elapsedTracker.resume() }
    }
    var isPaused: Bool { session?.state == .paused }
    var effectiveElapsed: TimeInterval {
        guard let sessionStart else { return 0 }
        return elapsedTracker.elapsed(since: sessionStart)
    }

    /// A poll refreshes the display/relay but deliberately does not add another
    /// aggregate sample; the builder delegate owns avg/max accounting.
    func applyPolledHeartRate(_ bpm: Double, sampleEnd: Date? = nil) {
        guard isActive || isMonitoring, hrSource == .appleWatch, bpm > 0 else { return }
        currentBPM = bpm
        relayReading(bpm, endingAt: sampleEnd)
    }

    /// The values one `HKLiveWorkoutBuilder` callback carries, extracted on
    /// HealthKit's own queue so nothing non-`Sendable` crosses into the main
    /// actor. The delegate boundary is kept in WatchWorkoutManagerHealthKit.
    struct CollectedSample: Sendable {
        var bpm: Double?
        var distanceMeters: Double?
        /// End of `bpm`'s HealthKit sample; identifies a reading the relay already sent.
        var bpmSampleEnd: Date?
    }

    /// Applies one builder callback's values on the main actor.
    func apply(_ sample: CollectedSample) {
        guard isActive || isMonitoring else { return }
        if let bpm = sample.bpm {
            currentBPM = bpm
            accumulatedHR += bpm
            hrCount += 1
            recordedHRSamples.append(HRSamplePoint(t: effectiveElapsed, bpm: bpm))
            if maxHeartRate == nil || bpm > (maxHeartRate ?? 0) { maxHeartRate = bpm }
            if hrSource == .appleWatch { relayReading(bpm, endingAt: sample.bpmSampleEnd) }
        }
        if let meters = sample.distanceMeters {
            distanceMeters = meters
            evaluateAutoPause(distance: meters)
        }
        if let sessionStart { elapsed = Date().timeIntervalSince(sessionStart) }
    }

    /// A lap/segment event the builder reported, applied on the main actor.
    func applyLapEvent() { autoLapCount += 1 }

    /// The workout session failed; tear everything down (main actor).
    func handleSessionFailure() { stopWorkout(save: false) }

    func handleSessionStateChange(_ state: HKWorkoutSessionState) {
        if state == .running {
            startHeartRatePolling()
            // Arms the heartbeat, which also reads the builder, so the phone
            // gets the first value even before a builder callback arrives.
            sendHeartRateToPhoneSoon()
        } else if (state == .ended || state == .stopped), isActive || isMonitoring {
            stopWorkout(save: false)
        }
    }

}
