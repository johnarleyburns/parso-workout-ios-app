import Foundation

/// What the Watch reports when the phone asks "what do you actually own?".
/// Carries identifiers and flags only: never BPM values or HealthKit IDs.
public struct WatchHRStateReport: Equatable, Sendable {
    public static let protocolVersion = 2
    public static let kind = "watch_hr_state_report"

    public let protocolVersion: Int
    public let isWorkoutActive: Bool
    public let healthKitRunning: Bool
    public let workoutType: String?
    public let adoptedRequestID: UUID?
    public let adoptedPhoneSessionID: UUID?
    /// A phone-launched workout that is still waiting for its start command.
    public let awaitingAdoption: Bool
    public let lastRealSampleAt: Date?
    /// Echo of the query being answered, so a delayed report is recognisable.
    public let queryIssuedAt: TimeInterval?

    public init(protocolVersion: Int = WatchHRStateReport.protocolVersion, isWorkoutActive: Bool,
                healthKitRunning: Bool, workoutType: String? = nil, adoptedRequestID: UUID? = nil,
                adoptedPhoneSessionID: UUID? = nil, awaitingAdoption: Bool = false,
                lastRealSampleAt: Date? = nil, queryIssuedAt: TimeInterval? = nil) {
        self.protocolVersion = protocolVersion
        self.isWorkoutActive = isWorkoutActive
        self.healthKitRunning = healthKitRunning
        self.workoutType = workoutType
        self.adoptedRequestID = adoptedRequestID
        self.adoptedPhoneSessionID = adoptedPhoneSessionID
        self.awaitingAdoption = awaitingAdoption
        self.lastRealSampleAt = lastRealSampleAt
        self.queryIssuedAt = queryIssuedAt
    }

    public init?(payload: [String: Any]) {
        guard payload["kind"] as? String == Self.kind,
              let version = payload["v"] as? Int,
              let active = payload["active"] as? Bool else { return nil }
        func uuid(_ key: String) -> UUID? { (payload[key] as? String).flatMap(UUID.init(uuidString:)) }
        self.init(protocolVersion: version, isWorkoutActive: active,
                  healthKitRunning: payload["running"] as? Bool ?? false,
                  workoutType: payload["type"] as? String,
                  adoptedRequestID: uuid("requestID"), adoptedPhoneSessionID: uuid("phoneWorkoutSessionID"),
                  awaitingAdoption: payload["awaitingAdoption"] as? Bool ?? false,
                  lastRealSampleAt: (payload["lastSampleAt"] as? Double).map(Date.init(timeIntervalSince1970:)),
                  queryIssuedAt: payload["queryIssuedAt"] as? Double)
    }

    public var payload: [String: Any] {
        var result: [String: Any] = ["kind": Self.kind, "v": protocolVersion, "active": isWorkoutActive,
                                     "running": healthKitRunning, "awaitingAdoption": awaitingAdoption]
        if let workoutType { result["type"] = workoutType }
        if let adoptedRequestID { result["requestID"] = adoptedRequestID.uuidString }
        if let adoptedPhoneSessionID { result["phoneWorkoutSessionID"] = adoptedPhoneSessionID.uuidString }
        if let lastRealSampleAt { result["lastSampleAt"] = lastRealSampleAt.timeIntervalSince1970 }
        if let queryIssuedAt { result["queryIssuedAt"] = queryIssuedAt }
        return result
    }
}

/// Readings the Watch measured while its phone-launched workout had no adopted
/// identifiers yet. Bounded; claimed only by a matching adoption, never by a
/// Watch-only workout or another phone session.
public struct WatchHRUnclaimedBuffer: Sendable {
    public struct Reading: Equatable, Sendable {
        public let bpm: Double
        public let sampleEnd: Date
        public let isHealthKit: Bool
    }

    public static let capacity = 120
    public private(set) var readings: [Reading] = []
    public private(set) var droppedCount = 0

    public init() {}

    public mutating func append(bpm: Double, sampleEnd: Date, isHealthKit: Bool) {
        if let last = readings.last, last.sampleEnd >= sampleEnd { return } // duplicate / heartbeat resend
        readings.append(Reading(bpm: bpm, sampleEnd: sampleEnd, isHealthKit: isHealthKit))
        if readings.count > Self.capacity {
            readings.removeFirst(readings.count - Self.capacity)
            droppedCount += 1
        }
    }

    /// Returns (and clears) readings inside the scoped session bounds.
    public mutating func claim(from start: Date, through end: Date) -> [Reading] {
        defer { readings.removeAll() }
        return readings.filter { $0.sampleEnd >= start && $0.sampleEnd <= end }
    }

    public mutating func discard() { readings.removeAll() }
    public var isEmpty: Bool { readings.isEmpty }
}
