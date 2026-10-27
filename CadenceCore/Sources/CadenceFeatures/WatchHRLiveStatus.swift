import Foundation

/// Non-durable Watch→phone liveness packet. It proves the interactive route
/// is alive while the sensor has no fresh reading; it carries no BPM and is
/// never journaled or sent via `transferUserInfo`.
public struct WatchHRLiveStatus: Equatable, Sendable {
    public static let key = "watchHRLiveStatusV1"
    public let requestID: UUID
    public let lastRealSampleEnd: Date?
    public let sensorHasFreshReading: Bool

    public init(requestID: UUID, lastRealSampleEnd: Date?, sensorHasFreshReading: Bool) {
        self.requestID = requestID
        self.lastRealSampleEnd = lastRealSampleEnd
        self.sensorHasFreshReading = sensorHasFreshReading
    }

    public var payload: [String: Any] {
        var result: [String: Any] = [Self.key: true, "requestID": requestID.uuidString]
        result["sensorHasFreshReading"] = sensorHasFreshReading
        if let lastRealSampleEnd { result["lastRealSampleEnd"] = lastRealSampleEnd.timeIntervalSince1970 }
        return result
    }

    public init?(payload: [String: Any]) {
        guard payload[Self.key] as? Bool == true,
              let raw = payload["requestID"] as? String,
              let requestID = UUID(uuidString: raw) else { return nil }
        self.requestID = requestID
        self.sensorHasFreshReading = payload["sensorHasFreshReading"] as? Bool ?? false
        self.lastRealSampleEnd = (payload["lastRealSampleEnd"] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
    }
}
