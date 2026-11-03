import Foundation

/// Small, versioned live-display HR packet carried over the mirrored
/// `HKWorkoutSession`. Transport only: the durable outbox stays the source of truth.
public struct WatchHRMirrorPacket: Codable, Equatable, Sendable {
    public static let version = 1
    public let protocolVersion: Int
    public let phoneWorkoutSessionID: UUID
    public let watchRequestID: UUID
    public let captureEpoch: UUID
    public let sampleEnd: TimeInterval
    public let bpm: Double

    public init(phoneWorkoutSessionID: UUID, watchRequestID: UUID,
                captureEpoch: UUID, sampleEnd: TimeInterval, bpm: Double) {
        self.protocolVersion = Self.version
        self.phoneWorkoutSessionID = phoneWorkoutSessionID
        self.watchRequestID = watchRequestID
        self.captureEpoch = captureEpoch
        self.sampleEnd = sampleEnd
        self.bpm = bpm
    }

    public var isValid: Bool {
        protocolVersion == Self.version && bpm.isFinite
            && bpm >= WatchHRMessage.minimumBPM && bpm <= WatchHRMessage.maximumBPM
            && sampleEnd.isFinite && sampleEnd > 0
    }
}

/// Pure scoping/freshness decision for a mirror packet.
public enum WatchHRMirrorRouting {
    public enum Decision: Equatable, Sendable {
        case accept
        case rejectedInvalid
        case rejectedRoute
        case stale
    }

    public static func decide(
        _ packet: WatchHRMirrorPacket,
        activeSessionID: UUID?,
        activeRequestID: UUID?,
        routeCaptureEpoch: UUID?,
        now: Date,
        staleAfter: TimeInterval = WatchHRRelay.staleAfter
    ) -> Decision {
        guard packet.isValid else { return .rejectedInvalid }
        guard packet.phoneWorkoutSessionID == activeSessionID,
              packet.watchRequestID == activeRequestID,
              packet.captureEpoch == routeCaptureEpoch else { return .rejectedRoute }
        guard now.timeIntervalSince1970 - packet.sampleEnd <= staleAfter else { return .stale }
        return .accept
    }

    public static func decode(_ chunks: [Data]) -> [WatchHRMirrorPacket] {
        chunks.compactMap { try? JSONDecoder().decode(WatchHRMirrorPacket.self, from: $0) }
    }
}
