import Foundation

/// Durable, versioned handoff for a cardio workout completed on Apple Watch.
/// The UUID belongs to the app's workout, not to a particular WCSession
/// delivery, so retries and HealthKit reconciliation can remain idempotent.
public struct WatchCardioCompletion: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let id: UUID
    public let type: CardioType
    public let title: String?
    public let start: Date
    public let end: Date
    public let distanceMeters: Double?
    public let hrSamples: [HRSamplePoint]
    public let avgHeartRate: Double?
    public let maxHeartRate: Double?
    public let gpsEnabled: Bool

    public init(id: UUID = UUID(), type: CardioType, title: String? = nil,
                start: Date, end: Date, distanceMeters: Double? = nil,
                hrSamples: [HRSamplePoint] = [], avgHeartRate: Double? = nil,
                maxHeartRate: Double? = nil, gpsEnabled: Bool = false,
                version: Int = currentVersion) {
        self.version = version; self.id = id; self.type = type; self.title = title
        self.start = start; self.end = end
        self.distanceMeters = gpsEnabled ? distanceMeters : nil
        self.hrSamples = hrSamples; self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate; self.gpsEnabled = gpsEnabled
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }

    public static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.version == currentVersion else { throw DecodeError.unsupportedVersion(value.version) }
        return value
    }

    public enum DecodeError: Error, Equatable { case unsupportedVersion(Int) }

    public var ingestedWorkout: IngestedWorkout {
        IngestedWorkout(id: id, type: type, start: start, end: end,
                        distanceMeters: distanceMeters,
                        avgHeartRate: avgHeartRate, maxHeartRate: maxHeartRate,
                        source: .watch, hrSamples: hrSamples,
                        importedKind: importedKind)
    }

    private var importedKind: ImportedWorkoutKind? {
        switch type {
        case .run: return .running
        case .walk: return .walking
        case .cycle: return .cycling
        case .swim: return .swimming
        case .rowing: return .rowing
        case .hiit: return .hiit
        case .boxing: return .boxing
        case .other: return .other
        }
    }
}
