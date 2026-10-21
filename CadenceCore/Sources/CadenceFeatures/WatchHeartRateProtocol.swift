import Foundation

/// Versioned, property-list-safe contract for durable Watch → phone heart-rate
/// delivery in a phone-started strength workout. The whole message travels as
/// one JSON `Data` value under `WatchHRMessage.payloadKey`, so it is valid for
/// `sendMessage` and `transferUserInfo` alike.
public enum WatchHRMessageKind: String, Codable, Sendable {
    case observations, finalizeRequest, finalizeAcknowledgement
}

public struct WatchHRObservation: Codable, Equatable, Sendable {
    public var observationID: UUID
    public var source: HeartRateObservationSource
    /// Original measurement end time (Unix seconds). Never the receipt time.
    public var sampleEnd: TimeInterval
    public var bpm: Double
    /// HealthKit sample identity when available.
    public var sampleID: String?
    public init(observationID: UUID, source: HeartRateObservationSource, sampleEnd: TimeInterval,
                bpm: Double, sampleID: String? = nil) {
        self.observationID = observationID; self.source = source
        self.sampleEnd = sampleEnd; self.bpm = bpm; self.sampleID = sampleID
    }
}

/// Protocol-level acknowledgement. `deliveryID` removes exactly that batch;
/// `cursor` is the highest sequence such that every batch 1...cursor was
/// persisted (a contiguous prefix), so reordered delivery never over-acknowledges.
public struct WatchHRAcknowledgement: Codable, Equatable, Sendable {
    public var deliveryID: UUID
    public var cursor: Int
    public init(deliveryID: UUID, cursor: Int) { self.deliveryID = deliveryID; self.cursor = cursor }
}

public enum WatchHRMessageRejection: String, Error, Sendable, Equatable {
    case malformed, unsupportedVersion, missingIdentifier, emptyBatch, invalidSequence
    case invalidBPM, invalidTimestamp, invalidSource
    case sessionMismatch, requestMismatch
}

public struct WatchHRMessage: Codable, Equatable, Sendable {
    public static let payloadKey = "watchHRv1"
    public static let currentVersion = 1
    public static let minimumBPM = 20.0
    public static let maximumBPM = 250.0

    public var version: Int
    public var kind: WatchHRMessageKind
    public var deliveryID: UUID
    public var phoneWorkoutSessionID: UUID
    public var watchRequestID: UUID
    /// Batch sequence (1-based, monotonic). For `finalizeAcknowledgement` it is
    /// the last batch sequence the Watch ever produced for this workout.
    public var sequence: Int
    public var observations: [WatchHRObservation]
    public var acknowledgement: WatchHRAcknowledgement?

    public init(version: Int = WatchHRMessage.currentVersion, kind: WatchHRMessageKind, deliveryID: UUID,
                phoneWorkoutSessionID: UUID, watchRequestID: UUID, sequence: Int = 0,
                observations: [WatchHRObservation] = [], acknowledgement: WatchHRAcknowledgement? = nil) {
        self.version = version; self.kind = kind; self.deliveryID = deliveryID
        self.phoneWorkoutSessionID = phoneWorkoutSessionID; self.watchRequestID = watchRequestID
        self.sequence = sequence; self.observations = observations; self.acknowledgement = acknowledgement
    }

    /// Property-list-safe dictionary for WatchConnectivity.
    public var payload: [String: Any] {
        let data = (try? JSONEncoder().encode(self)) ?? Data()
        return ["action": "watch_hr", Self.payloadKey: data]
    }

    public static func isWatchHRPayload(_ dictionary: [String: Any]) -> Bool {
        dictionary[payloadKey] != nil || dictionary["action"] as? String == "watch_hr"
    }

    /// Parses and structurally validates a payload. Routing (session/request
    /// match) is checked separately by `validateScope`.
    public static func parse(_ dictionary: [String: Any]) -> Result<WatchHRMessage, WatchHRMessageRejection> {
        guard let data = dictionary[payloadKey] as? Data else { return .failure(.malformed) }
        if let probe = try? JSONDecoder().decode(VersionProbe.self, from: data), probe.version != currentVersion {
            return .failure(.unsupportedVersion)
        }
        guard let message = try? JSONDecoder().decode(WatchHRMessage.self, from: data) else {
            return .failure(.malformed)
        }
        if let rejection = message.structuralRejection { return .failure(rejection) }
        return .success(message)
    }

    private struct VersionProbe: Decodable { let version: Int }

    var structuralRejection: WatchHRMessageRejection? {
        guard version == Self.currentVersion else { return .unsupportedVersion }
        switch kind {
        case .observations where acknowledgement != nil && observations.isEmpty:
            break // a pure acknowledgement carries no observations
        case .observations:
            guard !observations.isEmpty else { return .emptyBatch }
            guard sequence >= 1 else { return .invalidSequence }
            for o in observations {
                guard o.bpm.isFinite, o.bpm >= Self.minimumBPM, o.bpm <= Self.maximumBPM else { return .invalidBPM }
                guard o.sampleEnd.isFinite, o.sampleEnd > 0 else { return .invalidTimestamp }
            }
        case .finalizeRequest:
            break
        case .finalizeAcknowledgement:
            guard sequence >= 0 else { return .invalidSequence }
        }
        return nil
    }

    /// Whether this message belongs to the expected workout. Used by both sides.
    public func validateScope(phoneWorkoutSessionID expectedSession: UUID,
                              watchRequestID expectedRequest: UUID) -> WatchHRMessageRejection? {
        if phoneWorkoutSessionID != expectedSession { return .sessionMismatch }
        if watchRequestID != expectedRequest { return .requestMismatch }
        return nil
    }
}

/// Transport health, never inferred from an old display heartbeat.
public enum WatchHRTransportState: String, Equatable, Sendable {
    case idle, streaming, awaitingFinalization, pendingDelivery, failedRecoverably
}
