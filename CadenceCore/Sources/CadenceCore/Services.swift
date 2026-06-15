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

    public init(id: UUID, type: CardioType, start: Date, end: Date,
                distanceMeters: Double? = nil, activeEnergyKcal: Double? = nil,
                avgHeartRate: Double? = nil, maxHeartRate: Double? = nil,
                source: CardioSource = .watch, hrSamples: [HRSamplePoint] = []) {
        self.id = id; self.type = type; self.start = start; self.end = end
        self.distanceMeters = distanceMeters; self.activeEnergyKcal = activeEnergyKcal
        self.avgHeartRate = avgHeartRate; self.maxHeartRate = maxHeartRate
        self.source = source; self.hrSamples = hrSamples
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
    public init(id: UUID, start: Date, end: Date, activeEnergyKcal: Double? = nil) {
        self.id = id; self.start = start; self.end = end; self.activeEnergyKcal = activeEnergyKcal
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
}

// MARK: - Heart-rate monitor (FR-2.3, FR-4.4)

public enum HRMConnectionState: Equatable, Sendable {
    case poweredOff
    case unauthorized
    case idle
    case scanning
    case connecting(UUID)
    case connected(UUID)
    case reconnecting(UUID)
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
    func startScanning()
    func stopScanning()
    func connect(_ id: UUID)
    func disconnect()
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
