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
    public var lapCount: Int = 0
    public var manualLapCount: Int = 0
    public var splitPer500m: Double?
    public var isAutoPaused: Bool = false

    let unit: MeasurementUnitPreference
    let distanceUnit: DistanceUnitPreference
    let kind: WorkoutConfigurationSpec.CardioKind

    private var lastDistance: Double = 0
    private var lastDistanceTime: Date?
    private var distanceHistory: [(time: Date, dist: Double)] = []

    public init(kind: WorkoutConfigurationSpec.CardioKind, unit: MeasurementUnitPreference = .kilograms, distanceUnit: DistanceUnitPreference = .kilometers) {
        self.kind = kind
        self.unit = unit
        self.distanceUnit = distanceUnit
    }

    public func updateElapsed(_ s: TimeInterval) { elapsed = s }
    public func updateHR(_ bpm: Double?) {
        hrBPM = bpm
        if let bpm { hrZone = CardioMath.hrZone(bpm: bpm, maxHR: CardioMath.defaultMaxHR(age: nil)) }
    }
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
        if distanceUnit == .kilometers {
            if m >= 1000 { return String(format: "%.2f km", m / 1000) }
            return String(format: "%.0f m", m)
        } else {
            let miles = m / 1609.344
            return String(format: "%.2f mi", miles)
        }
    }

    public func formatPace() -> String {
        guard let sec = currentPaceSecPerKm, sec.isFinite, sec > 0 else { return "--" }
        let perUnit: Double = distanceUnit == .kilometers ? sec : sec * 1.609344
        let m = Int(perUnit) / 60, s = Int(perUnit) % 60
        let label = distanceUnit == .kilometers ? "/km" : "/mi"
        return String(format: "%d:%02d %@", m, s, label)
    }

    public func formatSpeed() -> String {
        guard let mps = currentSpeedMPS, mps.isFinite else { return "--" }
        if distanceUnit == .kilometers {
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
    public var warmupSeconds: Int
    public var workSeconds: Int
    public var restSeconds: Int
    public var cooldownSeconds: Int
    public var hiitProtocol: HIITProtocol = .tabata
    public var boxingRoundMinutes: Int = 3
    public var boxingRestSeconds: Int = 60

    public init(kind: String, warmupSeconds: Int? = nil, cooldownSeconds: Int? = nil) {
        self.kind = kind
        self.warmupSeconds = Self.clampOptionalDuration(warmupSeconds, fallback: 180, allowsZero: true)
        self.cooldownSeconds = Self.clampOptionalDuration(cooldownSeconds, fallback: 120, allowsZero: true)
        switch kind.lowercased() {
        case "hiit":
            self.rounds = 8; self.workSeconds = 20; self.restSeconds = 10
            self.hiitProtocol = .tabata
        case "boxing":
            self.rounds = 8; self.workSeconds = 180; self.restSeconds = 60
            self.boxingRoundMinutes = 3
            self.boxingRestSeconds = 60
        default:
            self.rounds = 8; self.workSeconds = 180; self.restSeconds = 60
        }
    }

    private static func clampOptionalDuration(_ value: Int?, fallback: Int, allowsZero: Bool) -> Int {
        let lower = allowsZero ? 0 : 5
        return max(lower, min(600, value ?? fallback))
    }

    public func clamped() -> IntervalSetupModel {
        let copy = IntervalSetupModel(kind: kind)
        copy.rounds = max(1, min(30, rounds))
        copy.warmupSeconds = max(0, min(600, warmupSeconds))
        copy.workSeconds = max(5, min(600, workSeconds))
        copy.restSeconds = max(5, min(600, restSeconds))
        copy.cooldownSeconds = max(0, min(600, cooldownSeconds))
        copy.hiitProtocol = hiitProtocol
        copy.boxingRoundMinutes = max(2, min(3, boxingRoundMinutes))
        copy.boxingRestSeconds = boxingRestSeconds <= 30 ? 30 : 60
        if kind.lowercased() == "boxing" {
            copy.rounds = max(1, min(20, rounds))
        }
        return copy
    }

    public func intervalPlan() -> IntervalPlan {
        let setup = clamped()
        return .custom(
            name: kind,
            warmup: TimeInterval(setup.warmupSeconds),
            rounds: setup.rounds,
            work: TimeInterval(setup.workSeconds),
            rest: TimeInterval(setup.restSeconds),
            cooldown: TimeInterval(setup.cooldownSeconds)
        )
    }

    public func hiitIntervalPlan() -> IntervalPlan {
        switch hiitProtocol {
        case .tabata: return .tabata()
        case .norwegian4x4: return .norwegian4x4()
        case .gibala: return .gibala()
        case .sit: return .sit()
        case .rehit: return .rehit()
        case .tenTwentyThirty: return .tenTwentyThirty()
        }
    }

    public func boxingIntervalPlan() -> IntervalPlan {
        let setup = clamped()
        return .boxing(rounds: setup.rounds, round: TimeInterval(setup.boxingRoundMinutes * 60), rest: TimeInterval(setup.boxingRestSeconds))
    }
}

public enum HIITProtocol: String, CaseIterable, Codable, Sendable, Identifiable {
    case tabata, norwegian4x4, gibala, sit, rehit, tenTwentyThirty
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .tabata: return "Tabata"
        case .norwegian4x4: return "Norwegian 4x4"
        case .gibala: return "Gibala"
        case .sit: return "SIT (Wingate)"
        case .rehit: return "REHIT"
        case .tenTwentyThirty: return "10-20-30"
        }
    }
}
