import Foundation

// Protocol abstractions over platform services (HealthKit, CoreBluetooth,
// CoreLocation). CadenceCore stays free of those frameworks so it remains
// cross-platform and unit-testable with `swift test`; the iOS app provides the
// real implementations and a fake is provided for previews/UI tests.

// MARK: - Activity / Steps (FR-3)

public struct DayActivity: Equatable, Sendable, Identifiable {
    public var date: Date
    public var steps: Int
    public var distanceMeters: Double
    public var flightsClimbed: Int
    public var activeEnergyKcal: Double
    public var id: Date { date }

    public init(date: Date, steps: Int, distanceMeters: Double = 0,
                flightsClimbed: Int = 0, activeEnergyKcal: Double = 0) {
        self.date = date
        self.steps = steps
        self.distanceMeters = distanceMeters
        self.flightsClimbed = flightsClimbed
        self.activeEnergyKcal = activeEnergyKcal
    }
}

// MARK: - Step health status (evidence-based, not a user setting)

public enum StepHealthStatus: String, Sendable, Equatable, CaseIterable {
    case low
    case building
    case onTrack

    public var displayName: String {
        switch self {
        case .low: return "Low"
        case .building: return "Building"
        case .onTrack: return "On track"
        }
    }
}

public struct StepActivitySummary: Equatable, Sendable {
    public static let floorDailySteps = 4_000
    public static let targetDailySteps = 8_000
    public static let weeklyTargetSteps = 56_000

    public let todaySteps: Int
    public let weeklyTotalSteps: Int
    public let sevenDayAverageSteps: Double
    public let status: StepHealthStatus

    public init(from activity: [DayActivity]) {
        let sorted = activity.sorted { $0.date > $1.date }
        self.todaySteps = sorted.first?.steps ?? 0
        self.weeklyTotalSteps = sorted.prefix(7).reduce(0) { $0 + $1.steps }
        let avg = sorted.isEmpty ? 0 : Double(sorted.prefix(7).reduce(0) { $0 + $1.steps }) / Double(min(7, sorted.count))
        self.sevenDayAverageSteps = avg

        if avg < Double(Self.floorDailySteps) {
            self.status = .low
        } else if avg < Double(Self.targetDailySteps) {
            self.status = .building
        } else {
            self.status = .onTrack
        }
    }

    public init(from activity: [DayActivity], targetDailySteps: Int) {
        let sorted = activity.sorted { $0.date > $1.date }
        self.todaySteps = sorted.first?.steps ?? 0
        self.weeklyTotalSteps = sorted.prefix(7).reduce(0) { $0 + $1.steps }
        let avg = sorted.isEmpty ? 0 : Double(sorted.prefix(7).reduce(0) { $0 + $1.steps }) / Double(min(7, sorted.count))
        self.sevenDayAverageSteps = avg

        let target = Double(targetDailySteps)
        if avg < Double(Self.floorDailySteps) {
            self.status = .low
        } else if avg < target {
            self.status = .building
        } else {
            self.status = .onTrack
        }
    }

    public static let empty = StepActivitySummary(from: [])
}

// MARK: - Ingested workout summary (FR-2.1)

/// A summary of a workout read back from HealthKit (e.g. one the Watch saved).
public struct IngestedWorkout: Equatable, Sendable, Identifiable {
    public var id: UUID                 // HealthKit workout UUID
    public var type: CardioType
    public var start: Date
    public var end: Date
    public var distanceMeters: Double?
    public var activeEnergyKcal: Double?
    public var avgHeartRate: Double?
    public var maxHeartRate: Double?
    public var source: CardioSource
    public var hrSamples: [HRSamplePoint]
    public var importedKind: ImportedWorkoutKind?

    public init(id: UUID, type: CardioType, start: Date, end: Date,
                distanceMeters: Double? = nil, activeEnergyKcal: Double? = nil,
                avgHeartRate: Double? = nil, maxHeartRate: Double? = nil,
                source: CardioSource = .watch, hrSamples: [HRSamplePoint] = [],
                importedKind: ImportedWorkoutKind? = nil) {
        self.id = id; self.type = type; self.start = start; self.end = end
        self.distanceMeters = distanceMeters; self.activeEnergyKcal = activeEnergyKcal
        self.avgHeartRate = avgHeartRate; self.maxHeartRate = maxHeartRate
        self.source = source; self.hrSamples = hrSamples
        self.importedKind = importedKind
    }
}

/// Preserved HealthKit workout activity type so the coach can distinguish
/// imported strength from unknown cardio rather than mapping all to .other.
public enum ImportedWorkoutKind: String, Sendable, CaseIterable {
    case traditionalStrength
    case functionalStrength
    case running
    case walking
    case cycling
    case swimming
    case rowing
    case hiit
    case boxing
    case other

    public var isStrength: Bool {
        self == .traditionalStrength || self == .functionalStrength
    }
}

public struct HRSamplePoint: Equatable, Sendable {
    public var t: TimeInterval   // seconds since workout start
    public var bpm: Double
    public init(t: TimeInterval, bpm: Double) { self.t = t; self.bpm = bpm }
}

/// Summary of a strength session to write back to HealthKit (FR-4.3).
public struct StrengthWorkoutSummary: Equatable, Sendable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var activeEnergyKcal: Double?
    public var hrSamples: [HRSamplePoint]
    public var avgHR: Double?
    public var maxHR: Double?
    public init(id: UUID, start: Date, end: Date, activeEnergyKcal: Double? = nil,
                hrSamples: [HRSamplePoint] = [], avgHR: Double? = nil, maxHR: Double? = nil) {
        self.id = id; self.start = start; self.end = end; self.activeEnergyKcal = activeEnergyKcal
        self.hrSamples = hrSamples; self.avgHR = avgHR; self.maxHR = maxHR
    }
}

/// Summary of a recorded cardio workout to write back to HealthKit (FR-2.5).
public struct CardioWorkoutSummary: Equatable, Sendable {
    public var id: UUID
    public var type: CardioType
    public var start: Date
    public var end: Date
    public var distanceMeters: Double?
    public var activeEnergyKcal: Double?
    public var hrSamples: [HRSamplePoint]
    public var route: [LocationFix]
    /// Interval (HIIT/boxing) structure, when this is a recorded interval workout.
    public var intervalSummary: IntervalSummary?
    /// Free-text label for an "Other Cardio" workout (e.g. "Rowing"); nil ⇒ type
    /// name (feedback batch 6).
    public var customTitle: String?
    /// Manually logged vs live-recorded (feedback batch 6).
    public var isLogged: Bool
    /// Optional distance goal in meters (feedback batch 8); nil ⇒ no goal set.
    public var targetDistanceMeters: Double?
    public init(id: UUID, type: CardioType, start: Date, end: Date,
                distanceMeters: Double? = nil, activeEnergyKcal: Double? = nil,
                hrSamples: [HRSamplePoint] = [], route: [LocationFix] = [],
                intervalSummary: IntervalSummary? = nil,
                customTitle: String? = nil, isLogged: Bool = false,
                targetDistanceMeters: Double? = nil) {
        self.id = id; self.type = type; self.start = start; self.end = end
        self.distanceMeters = distanceMeters; self.activeEnergyKcal = activeEnergyKcal
        self.hrSamples = hrSamples; self.route = route
        self.intervalSummary = intervalSummary
        self.customTitle = customTitle; self.isLogged = isLogged
        self.targetDistanceMeters = targetDistanceMeters
    }
}

public enum HealthAuthorizationStatus: String, Sendable {
    case notDetermined, authorized, denied, unavailable
}

/// Abstraction over HealthKit reads/writes (FR-3, FR-2.1, FR-4.1/4.3).
public protocol HealthDataProviding: AnyObject, Sendable {
    var isHealthDataAvailable: Bool { get }
    func requestAuthorization() async -> HealthAuthorizationStatus
    func todayActivity() async -> DayActivity
    /// Most-recent-first daily activity, `days` entries ending today.
    func activityTrend(days: Int) async -> [DayActivity]
    /// Workouts saved after `since` (e.g. by the Watch), for ingest (FR-2.1).
    func newWorkouts(since: Date?) async -> [IngestedWorkout]
    /// Write a summary strength workout (FR-4.3). Returns the HK UUID on success.
    func saveStrengthWorkout(_ summary: StrengthWorkoutSummary) async -> UUID?
    /// Write a recorded cardio workout with HR + route (FR-2.5).
    func saveCardioWorkout(_ summary: CardioWorkoutSummary) async -> UUID?
    /// Passive recovery samples (HRV SDNN, resting HR, sleep hours) for the trailing
    /// `days`, one per calendar day where data exists (revenue Phase 4). On-device
    /// reads only — never egresses, so the Data Not Collected label is unaffected.
    func passiveReadinessSamples(days: Int) async -> [PassiveReadinessSample]
}

public extension HealthDataProviding {
    /// Default: no passive data (keeps fakes/mocks and older conformers compiling).
    func passiveReadinessSamples(days: Int) async -> [PassiveReadinessSample] { [] }
}

// MARK: - Heart-rate monitor (FR-2.3, FR-4.4)

public enum HRMConnectionState: Equatable, Sendable {
    case poweredOff
    case unauthorized
    case idle
    case scanning
    case connecting(UUID)
    case connected(UUID)
    case reconnecting(UUID, attempts: Int = 0)
    case reconnectionFailed(UUID, error: String? = nil)
}

public struct DiscoveredHRM: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var rssi: Int
    public init(id: UUID, name: String, rssi: Int = 0) {
        self.id = id; self.name = name; self.rssi = rssi
    }
}

/// Abstraction over a BLE Heart-Rate Service (0x180D) monitor.
public protocol HeartRateMonitoring: AnyObject {
    var state: HRMConnectionState { get }
    var currentBPM: Double? { get }
    var battery: Int? { get }
    var connectionError: String? { get }
    var criticalBattery: Bool { get }
    /// Straps discovered while scanning (0x180D advertisers).
    var discovered: [DiscoveredHRM] { get }
    func startScanning()
    func stopScanning()
    func connect(_ id: UUID)
    func disconnect()
    func restoreDefaultDevice(_ id: UUID)
    func injectExternalBPM(_ bpm: Double)
}

// MARK: - HR source (Watch-native vs BLE chest strap)

public enum HRSource: String, CaseIterable, Codable, Sendable {
    case appleWatch
    case bluetooth

    public var displayName: String {
        switch self {
        case .appleWatch: return "Apple Watch"
        case .bluetooth: return "Chest Strap"
        }
    }

    public var symbol: String {
        switch self {
        case .appleWatch: return "applewatch"
        case .bluetooth: return "sensor.tag.radiowaves.forward"
        }
    }
}

// MARK: - Location tracking (FR-2.2)

public struct LocationFix: Equatable, Sendable {
    public var t: TimeInterval
    public var lat: Double
    public var lon: Double
    public var elevation: Double
    public var horizontalAccuracy: Double
    public init(t: TimeInterval, lat: Double, lon: Double, elevation: Double = 0, horizontalAccuracy: Double = 0) {
        self.t = t; self.lat = lat; self.lon = lon; self.elevation = elevation
        self.horizontalAccuracy = horizontalAccuracy
    }
}

public protocol LocationTracking: AnyObject {
    var fixes: [LocationFix] { get }
    func start()
    func stop()
}

public extension LocationTracking {
    /// Total path length of the recorded fixes, in meters. A default so callers
    /// depending only on the protocol (e.g. `CardioRecorder`) get distance for free.
    var distanceMeters: Double { GeoMath.pathDistance(fixes) }
}

// MARK: - Distance helper

public enum GeoMath {
    /// Haversine distance in meters between two coordinates.
    public static func distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Total path length in meters for an ordered list of fixes.
    public static func pathDistance(_ fixes: [LocationFix]) -> Double {
        guard fixes.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<fixes.count {
            total += distance(lat1: fixes[i-1].lat, lon1: fixes[i-1].lon,
                              lat2: fixes[i].lat, lon2: fixes[i].lon)
        }
        return total
    }
}
