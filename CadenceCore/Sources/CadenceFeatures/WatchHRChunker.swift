import Foundation

/// Splits Watch heart-rate observations into transport chunks whose
/// property-list encoded size stays under `maxEncodedBytes`, well below
/// WatchConnectivity payload limits.
public struct WatchHRChunker: Sendable {
    public static let maxEncodedBytes = 48 * 1024
    public static let maxObservationsPerChunk = 30

    public var phoneWorkoutSessionID: UUID
    public var watchRequestID: UUID
    public var captureEpoch: UUID
    public var maxBytes: Int
    public var maxObservations: Int

    public init(phoneWorkoutSessionID: UUID, watchRequestID: UUID, captureEpoch: UUID,
                maxBytes: Int = WatchHRChunker.maxEncodedBytes,
                maxObservations: Int = WatchHRChunker.maxObservationsPerChunk) {
        self.phoneWorkoutSessionID = phoneWorkoutSessionID; self.watchRequestID = watchRequestID
        self.captureEpoch = captureEpoch; self.maxBytes = maxBytes; self.maxObservations = max(1, maxObservations)
    }

    /// Property-list encoded size of the full envelope carrying `observations`;
    /// `Int.max` when it cannot be encoded.
    public func encodedSize(_ observations: [WatchHRObservation]) -> Int {
        let message = WatchHRMessage(kind: .observations, deliveryID: UUID(), phoneWorkoutSessionID: phoneWorkoutSessionID,
                                     watchRequestID: watchRequestID, captureEpoch: captureEpoch,
                                     sequence: Int(Int32.max), observations: observations)
        guard let data = try? JSONEncoder().encode(message) else { return .max }
        let dict: [String: Any] = ["action": "watch_hr", WatchHRMessage.payloadKey: data]
        guard let plist = try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        else { return .max }
        return plist.count
    }

    /// Greedy, order-preserving split. Never drops an observation: a single
    /// observation that alone exceeds the budget still forms its own chunk
    /// (callers detect that with `encodedSize` and surface a recoverable failure).
    public func chunks(_ samples: [WatchHRObservation]) -> [[WatchHRObservation]] {
        var out: [[WatchHRObservation]] = []
        var current: [WatchHRObservation] = []
        for sample in samples {
            if !current.isEmpty {
                let candidate = current + [sample]
                if candidate.count > maxObservations || encodedSize(candidate) > maxBytes {
                    out.append(current); current = []
                }
            }
            current.append(sample)
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

/// Privacy-safe transport counters: no timestamps, BPM values or identifiers.
public struct WatchHRTransportDiagnostics: Equatable, Sendable {
    public var observationCount = 0
    public var chunkCount = 0
    public var largestChunkBytes = 0
    public var retryCount = 0
    public var receiptCount = 0
    public var oversizedChunkCount = 0
    public init() {}
}
