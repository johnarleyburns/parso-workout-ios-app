import Foundation
import HealthKit
import WatchConnectivity
import WatchKit
import CadenceCore
import CadenceFeatures

@Observable
final class WatchWorkoutManager: NSObject {

    // MARK: Published state

    private(set) var currentBPM: Double?
    private(set) var isActive: Bool = false
    private(set) var isMonitoring: Bool = false
    private(set) var workoutType: String?

    var hrSource: HRSource {
        get { HRSource(rawValue: hrSourceRaw) ?? .appleWatch }
        set { hrSourceRaw = newValue.rawValue }
    }

    private(set) var hrAuthorized: Bool = false
    private(set) var workoutShareAuthorized: Bool = false
    private(set) var bleState: BLEConnectionState? = nil
    private(set) var bleBattery: Int? = nil

    private(set) var elapsed: TimeInterval = 0
    private(set) var activeEnergyKcal: Double = 0
    private(set) var avgHeartRate: Double?
    private(set) var maxHeartRate: Double?
    private(set) var distanceMeters: Double = 0
    var savedSummary: SavedWorkoutSummary?

    struct SavedWorkoutSummary {
        let duration: TimeInterval, avgHR: Double?, maxHR: Double?, activeKcal: Double, distanceMeters: Double
    }

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
    private var sessionStart: Date?
    private var accumulatedHR: Double = 0
    private var hrCount: Int = 0
    var watchAppSettings: AppSettings?

    private let uiTestMode: Bool

    init(uiTestMode: Bool = false) {
        self.uiTestMode = uiTestMode
        super.init()
    }

    private var wcSession: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    // MARK: WCSession activation

    func activateWCSession() {
        guard let session = wcSession else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: HealthKit authorization

    @discardableResult
    func requestWorkoutAuthorization() async -> Bool {
        guard !uiTestMode else {
            workoutShareAuthorized = true
            hrAuthorized = true
            return true
        }
        let hrType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        var shareTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.quantityType(forIdentifier: .distanceSwimming)!,
        ]
        if #available(watchOS 11.0, *) {
            if let rowing = HKObjectType.quantityType(forIdentifier: .distanceRowing) {
                shareTypes.insert(rowing)
            }
        }
        let readTypes: Set<HKObjectType> = [
            hrType,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.quantityType(forIdentifier: .distanceSwimming)!,
        ]
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            let wStatus = store.authorizationStatus(for: HKObjectType.workoutType())
            workoutShareAuthorized = (wStatus == .sharingAuthorized)
            let hStatus = store.authorizationStatus(for: hrType)
            hrAuthorized = (hStatus != .notDetermined)
            return workoutShareAuthorized
        } catch {
            return false
        }
    }

    // MARK: Workout control

    func startWorkout(type rawType: String, cardioType: CardioType? = nil, spec: WorkoutConfigurationSpec? = nil) {
        guard !isActive else { return }
        workoutType = rawType
        isActive = true; isMonitoring = false
        let activity = Self.activityType(for: rawType)
        if uiTestMode { sessionStart = Date(); beginSession(activity: activity, spec: spec); return }
        Task {
            guard await requestWorkoutAuthorization() else { isActive = false; return }
            await MainActor.run { beginSession(activity: activity, spec: spec) }
        }
    }

    func startMonitoringSession() {
        guard !isActive, !isMonitoring else { return }
        isMonitoring = true; workoutType = "monitoring"
        if uiTestMode { sessionStart = Date(); beginSession(activity: .other); return }
        Task {
            guard await requestWorkoutAuthorization() else { isMonitoring = false; return }
            await MainActor.run { beginSession(activity: .other) }
        }
    }

    func stopMonitoringSession() {
        guard isMonitoring else { return }
        stopWorkout(save: false)
    }

    func stopWorkout(save: Bool = true) {
        guard isActive || isMonitoring else { return }
        if save, let s = sessionStart {
            elapsed = Date().timeIntervalSince(s)
            let avg: Double? = hrCount > 0 ? (accumulatedHR / Double(hrCount)) : nil
            savedSummary = SavedWorkoutSummary(duration: elapsed, avgHR: avg, maxHR: maxHeartRate, activeKcal: activeEnergyKcal, distanceMeters: distanceMeters)
        }
        let b = builder; let s = session
        builder = nil; session = nil; extendedSession?.invalidate(); extendedSession = nil
        ble?.disconnect(); ble = nil; currentBPM = nil
        isActive = false; isMonitoring = false; workoutType = nil; bleState = nil
        sessionStart = nil; accumulatedHR = 0; hrCount = 0
        isSwimSession = false; isOutdoorSession = false
        autoPauseDetector.reset(); lastAutoPauseDistance = 0
        elapsed = 0; activeEnergyKcal = 0; avgHeartRate = nil; maxHeartRate = nil; distanceMeters = 0
        if let b, let s {
            b.endCollection(withEnd: Date()) { _, _ in save ? b.finishWorkout(completion: {_,_ in}) : b.discardWorkout() }
            s.end()
        }
    }

    func liveSummary() -> (duration: TimeInterval, avgHR: Double?, maxHR: Double?, activeKcal: Double, distanceMeters: Double) {
        if let start = sessionStart {
            elapsed = Date().timeIntervalSince(start)
        }
        let avg: Double? = hrCount > 0 ? (accumulatedHR / Double(hrCount)) : nil
        return (elapsed, avg, maxHeartRate, activeEnergyKcal, distanceMeters)
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

    // MARK: HR source switching

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
                    if self.maxHeartRate == nil || value > (self.maxHeartRate ?? 0) {
                        self.maxHeartRate = value
                    }
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

    private var autoPauseDetector = AutoPauseDetector()
    private(set) var manualLapCount: Int = 0
    private(set) var autoLapCount: Int = 0
    private var isSwimSession: Bool = false
    private var isOutdoorSession: Bool = false

    func incrementManualLap() { manualLapCount += 1 }
    func enableWaterLock() { WKInterfaceDevice.current().enableWaterLock() }
    func togglePause() {
        guard let s = session else { return }
        if s.state == .running { s.pause() } else if s.state == .paused { s.resume() }
    }
    var isPaused: Bool { session?.state == .paused }

    private func beginSession(activity: HKWorkoutActivityType, spec: WorkoutConfigurationSpec? = nil) {
        let config = HKWorkoutConfiguration()
        config.activityType = activity; config.locationType = .indoor
        if let spec {
            switch spec.location {
            case .indoor: break
            case .outdoor: config.locationType = .outdoor; isOutdoorSession = true
            case .pool(let lapLength):
                config.swimmingLocationType = .pool; isSwimSession = true
                if #available(watchOS 10.0, *) { config.lapLength = HKQuantity(unit: .meter(), doubleValue: lapLength) }
            case .openWater: config.swimmingLocationType = .openWater; isSwimSession = true
            }
        }
        sessionStart = Date(); autoPauseDetector.reset(); manualLapCount = 0; autoLapCount = 0
        guard !uiTestMode else { return }
        do {
            let s = try HKWorkoutSession(healthStore: store, configuration: config)
            self.session = s
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            b.delegate = self; self.builder = b; s.delegate = self
            s.startActivity(with: Date())
            b.beginCollection(withStart: Date(), completion: { _, _ in })
            extendedSession = WKExtendedRuntimeSession()
            extendedSession?.delegate = self; extendedSession?.start()
            if hrSource == .bluetooth { startBLE() }
            if isSwimSession { enableWaterLock() }
        } catch { isActive = false; isMonitoring = false; session = nil; builder = nil; sessionStart = nil }
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

extension WatchWorkoutManager {
    enum BLEConnectionState { case scanning, connected, disconnected }
}

// MARK: - WCSessionDelegate / Session / Builder delegates

extension WatchWorkoutManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handleMessage(message) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) { handleMessage(message); replyHandler(["ack": true]) }
    private func handleMessage(_ message: [String: Any]) {
        if message["command"] as? String == "start_workout", let type = message["type"] as? String { startWorkout(type: type) }
        else if message["command"] as? String == "stop_workout" { stopWorkout(save: false) }
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let s = watchAppSettings else { return }
        if let raw = applicationContext["settings.unit"] as? String, let unit = MeasurementUnitPreference(rawValue: raw) { s.unit = unit }
        if let cb = applicationContext["settings.intervalColorBlind"] as? Bool { s.intervalColorBlind = cb }
        if let rs = applicationContext["settings.restSeconds"] as? Int { s.restSeconds = rs }
        if let cm = applicationContext["settings.cooldownMinutes"] as? Int { s.cooldownMinutes = cm }
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        stopWorkout(save: false)
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard isActive || isMonitoring else { return }

        let hrType = HKQuantityType(.heartRate)
        if collectedTypes.contains(hrType),
           let stats = workoutBuilder.statistics(for: hrType),
           let qty = stats.mostRecentQuantity() {
            let bpm = qty.doubleValue(for: HKUnit(from: "count/min"))
            Task { @MainActor in
                self.currentBPM = bpm
                self.accumulatedHR += bpm
                self.hrCount += 1
                if self.maxHeartRate == nil || bpm > (self.maxHeartRate ?? 0) {
                    self.maxHeartRate = bpm
                }
                if hrSource == .appleWatch {
                    self.relayBPM(bpm)
                }
            }
        }

        let energyType = HKQuantityType(.activeEnergyBurned)
        if collectedTypes.contains(energyType),
           let stats = workoutBuilder.statistics(for: energyType),
           let qty = stats.sumQuantity() {
            let kcal = qty.doubleValue(for: HKUnit.kilocalorie())
            Task { @MainActor in self.activeEnergyKcal = kcal }
        }

        let distanceTypes: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
        for id in distanceTypes {
            let dt = HKQuantityType(id)
            if collectedTypes.contains(dt),
               let stats = workoutBuilder.statistics(for: dt),
               let qty = stats.sumQuantity() {
                let m = qty.doubleValue(for: HKUnit.meter())
                Task { @MainActor in
                    self.distanceMeters = m
                    self.evaluateAutoPause(distance: m)
                }
            }
        }
        if #available(watchOS 11.0, *) {
            let rowType = HKQuantityType(.distanceRowing)
            if collectedTypes.contains(rowType),
               let stats = workoutBuilder.statistics(for: rowType),
               let qty = stats.sumQuantity() {
                let m = qty.doubleValue(for: HKUnit.meter())
                Task { @MainActor in self.distanceMeters = m }
            }
        }

        if let elapsedTime = sessionStart {
            Task { @MainActor in self.elapsed = Date().timeIntervalSince(elapsedTime) }
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        guard let event = workoutBuilder.workoutEvents.last else { return }
        if event.type == .lap || event.type == .segment {
            Task { @MainActor in self.autoLapCount += 1 }
        }
    }
}
extension WatchWorkoutManager: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {}
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}
}
