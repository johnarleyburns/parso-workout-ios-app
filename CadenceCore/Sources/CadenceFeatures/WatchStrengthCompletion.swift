import Foundation
import CadenceCore

/// Identity of one Watch-started strength workout's completion HR transfer.
/// Independent of any phone-launch identity: the Watch mints it itself.
public struct WatchStrengthCompletionRoute: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let transferID: UUID
    public let captureEpoch: UUID
    public init(sessionID: UUID, transferID: UUID, captureEpoch: UUID) {
        self.sessionID = sessionID; self.transferID = transferID; self.captureEpoch = captureEpoch
    }
}

public enum WatchStrengthCompletionKey {
    public static let transferID = "hr_transfer_id"
    public static let captureEpoch = "hr_capture_epoch"
    public static let finalSequence = "hr_final_sequence"
}

/// Watch-side durable, receipt-backed chunk journal for a Watch-started workout's
/// completion HR. Chunks are removed only by a phone receipt.
@MainActor
public final class WatchStrengthCompletionOutbox {
    public let outbox: WatchHeartRateOutbox
    public init(outbox: WatchHeartRateOutbox) { self.outbox = outbox }

    /// Encodes finalized samples as observations and journals them as chunks.
    /// Returns the final sequence watermark, or nil if it could not be persisted.
    public func enqueue(samples: [HRSamplePoint], startedAt: Date, route: WatchStrengthCompletionRoute) -> Int? {
        guard outbox.bind(phoneWorkoutSessionID: route.sessionID, watchRequestID: route.transferID,
                          captureEpoch: route.captureEpoch) else { return nil }
        let base = startedAt.timeIntervalSince1970
        return outbox.sealCompletion(samples.map { (bpm: $0.bpm, sampleEnd: base + $0.t) })
    }

    public func flush() { outbox.flush() }
    public func retry(reason: String) { outbox.retry(reason: reason) }
    @discardableResult
    public func handleAcknowledgement(_ message: WatchHRMessage) -> Bool { outbox.handleAcknowledgement(message) }

    /// True when a chunk could not be delivered or persisted and is being retained.
    public var failedRecoverably: Bool { outbox.failedRecoverably }
    public var hasUnacknowledgedChunks: Bool { outbox.unacknowledgedCount > 0 }
}
