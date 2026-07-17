import Foundation
import CadenceCore

public struct WorkoutConfigurationSpec: Equatable {
    public enum CardioKind: Equatable {
        case run, walk, cycle, swim, hiit, boxing, rowing, other, strength
    }
    public enum Location: Equatable, Hashable {
        case indoor, outdoor, pool(lapLength: Double), openWater
    }
    public let kind: CardioKind
    public let location: Location

    public init(kind: CardioKind, location: Location = .indoor) {
        self.kind = kind
        self.location = location
    }

    public init(for rawType: String) {
        switch rawType.lowercased() {
        case "run": self.kind = .run; self.location = .outdoor
        case "walk": self.kind = .walk; self.location = .outdoor
        case "cycle": self.kind = .cycle; self.location = .indoor
        case "swim": self.kind = .swim; self.location = .pool(lapLength: 25)
        case "hiit": self.kind = .hiit; self.location = .indoor
        case "boxing": self.kind = .boxing; self.location = .indoor
        case "rowing": self.kind = .rowing; self.location = .indoor
        case "other": self.kind = .other; self.location = .indoor
        default: self.kind = .strength; self.location = .indoor
        }
    }
}

@Observable
public final class CardioMetricsModel {
    public var elapsed: TimeInterval = 0
    public var distanceMeters: Double = 0
    public var currentPaceSecPerKm: Double?
    public var currentSpeedMPS: Double?
    public var hrBPM: Double?
    public var hrZone: Int = 0
    public var activeKcal: Double = 0
    public var lapCount: Int = 0
    public var manualLapCount: Int = 0
    public var splitPer500m: Double?
    public var isAutoPaused: Bool = false

    let unit: MeasurementUnitPreference
    let kind: WorkoutConfigurationSpec.CardioKind

    private var lastDistance: Double = 0
    private var lastDistanceTime: Date?
    private var distanceHistory: [(time: Date, dist: Double)] = []

    public init(kind: WorkoutConfigurationSpec.CardioKind, unit: MeasurementUnitPreference = .kilograms) {
        self.kind = kind
        self.unit = unit
    }

    public func updateElapsed(_ s: TimeInterval) { elapsed = s }
    public func updateHR(_ bpm: Double?) {
        hrBPM = bpm
        if let bpm { hrZone = CardioMath.hrZone(bpm: bpm, maxHR: CardioMath.defaultMaxHR(age: nil)) }
    }
    public func updateKcal(_ kcal: Double) { activeKcal = kcal }
    public func updateDistance(_ m: Double) {
        distanceMeters = m
        recomputeSplitPer500m()
        let now = Date()
        distanceHistory.append((now, m))
        while let first = distanceHistory.first, now.timeIntervalSince(first.time) > 30 {
            distanceHistory.removeFirst()
        }
        if let first = distanceHistory.first, now.timeIntervalSince(first.time) > 3,
           m > first.dist {
            let deltaDist = m - first.dist
            let deltaTime = now.timeIntervalSince(first.time)
            currentPaceSecPerKm = deltaTime / max(0.001, deltaDist / 1000)
            currentSpeedMPS = deltaDist / max(0.001, deltaTime)
        }
        if let prev = lastDistanceTime {
            let dt = now.timeIntervalSince(prev)
            if dt > 0 {
                let ds = m - lastDistance
                if ds > 0 { currentSpeedMPS = ds / dt }
            }
        }
        lastDistance = m
        lastDistanceTime = now
    }

    public func resetAutoPause() { isAutoPaused = false }
    public func setAutoPaused(_ paused: Bool) { isAutoPaused = paused }

    public func formatDistance() -> String {
        let m = distanceMeters
        if unit == .kilograms {
            if m >= 1000 { return String(format: "%.2f km", m / 1000) }
            return String(format: "%.0f m", m)
        } else {
            let miles = m / 1609.344
            return String(format: "%.2f mi", miles)
        }
    }

    public func formatPace() -> String {
        guard let sec = currentPaceSecPerKm, sec.isFinite, sec > 0 else { return "--" }
        let perUnit: Double = unit == .kilograms ? sec : sec * 1.609344
        let m = Int(perUnit) / 60, s = Int(perUnit) % 60
        let label = unit == .kilograms ? "/km" : "/mi"
        return String(format: "%d:%02d %@", m, s, label)
    }

    public func formatSpeed() -> String {
        guard let mps = currentSpeedMPS, mps.isFinite else { return "--" }
        if unit == .kilograms {
            return String(format: "%.1f km/h", mps * 3.6)
        } else {
            return String(format: "%.1f mph", mps * 2.23694)
        }
    }

    public func recomputeSplitPer500m() {
        let m = distanceMeters
        let s = elapsed
        guard m > 0, s > 0 else { splitPer500m = nil; return }
        splitPer500m = (s / m) * 500
    }

    public func formatSplit() -> String {
        guard let split = splitPer500m else { return "--" }
        let m = Int(split) / 60, s = Int(split) % 60
        return String(format: "%d:%02d /500m", m, s)
    }
}

public struct AutoPauseDetector {
    public enum Action: Equatable { case pause, resume, none }
    private let speedThreshold: Double
    private let debounceSeconds: Double
    private var isStopped: Bool = false
    private var stopStart: Date?

    public init(speedThreshold: Double = 0.5, debounceSeconds: Double = 3.0) {
        self.speedThreshold = speedThreshold
        self.debounceSeconds = debounceSeconds
    }

    public mutating func evaluate(speedMPS: Double?, isDisabled: Bool, now: Date = Date()) -> Action {
        guard !isDisabled, let speed = speedMPS else { return .none }
        if speed < speedThreshold {
            if !isStopped {
                isStopped = true
                stopStart = now
            }
            if let start = stopStart, now.timeIntervalSince(start) >= debounceSeconds {
                return .pause
            }
        } else {
            if isStopped {
                isStopped = false
                stopStart = nil
                return .resume
            }
        }
        return .none
    }

    public mutating func reset() {
        isStopped = false
        stopStart = nil
    }
}

@Observable
public final class IntervalSetupModel {
    public let kind: String
    public var rounds: Int
    public var workSeconds: Int
    public var restSeconds: Int

    public init(kind: String) {
        self.kind = kind
        switch kind.lowercased() {
        case "hiit":
            self.rounds = 8; self.workSeconds = 30; self.restSeconds = 30
        default:
            self.rounds = 8; self.workSeconds = 180; self.restSeconds = 60
        }
    }

    public func clamped() -> IntervalSetupModel {
        let copy = IntervalSetupModel(kind: kind)
        copy.rounds = max(1, min(30, rounds))
        copy.workSeconds = max(5, min(600, workSeconds))
        copy.restSeconds = max(5, min(600, restSeconds))
        return copy
    }

    public func intervalPlan() -> IntervalPlan {
        .custom(name: kind, warmup: 180, rounds: max(1, min(30, rounds)),
                work: TimeInterval(max(5, min(600, workSeconds))),
                rest: TimeInterval(max(5, min(600, restSeconds))),
                cooldown: 120)
    }
}
