import Foundation

/// Watch-side ordering gate for phone snapshots.
///
/// The envelope travels with its decoded snapshot through decode, durable
/// persistence, and ACK, so a late completion can never apply one snapshot and
/// acknowledge another. A snapshot is committed (applied record saved and ACK
/// sent) only after every advertised component, including custom exercises, is
/// durable. Pure and synchronous: callers serialize it on one actor.
public struct WatchSyncCommitCoordinator: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        /// Everything is durable: persist this record, then acknowledge it.
        case commit(WatchSyncAppliedRecord)
        /// Wait for the custom-exercise store before committing.
        case awaitDurable
        /// Superseded by a newer snapshot or already confirmed; do nothing.
        case discard
        /// Durable write failed: keep the old confirmed revision, do not ACK, retry.
        case failed
    }

    /// Highest revision accepted for application in this process.
    public private(set) var highestAccepted: Int
    /// Snapshot waiting for its custom exercises to persist.
    public private(set) var awaiting: WatchSyncHandshake.Envelope?

    public init(appliedRevision: Int = 0) {
        highestAccepted = appliedRevision
    }

    public mutating func accept(_ envelope: WatchSyncHandshake.Envelope, applied: WatchSyncAppliedRecord?,
                                needsDurableExercises: Bool) -> Outcome {
        guard envelope.protocolVersion == WatchSyncHandshake.protocolVersion,
              envelope.revision > (applied?.revision ?? 0),
              envelope.revision >= highestAccepted else { return .discard }
        highestAccepted = envelope.revision
        if needsDurableExercises {
            awaiting = envelope
            return .awaitDurable
        }
        awaiting = nil
        return .commit(Self.record(envelope))
    }

    /// Reports the custom-exercise store result for `envelope`.
    public mutating func durableStoreFinished(for envelope: WatchSyncHandshake.Envelope, succeeded: Bool,
                                              applied: WatchSyncAppliedRecord?) -> Outcome {
        guard awaiting == envelope, envelope.revision > (applied?.revision ?? 0) else { return .discard }
        awaiting = nil
        guard succeeded else {
            highestAccepted = applied?.revision ?? 0
            return .failed
        }
        return .commit(Self.record(envelope))
    }

    private static func record(_ envelope: WatchSyncHandshake.Envelope) -> WatchSyncAppliedRecord {
        WatchSyncAppliedRecord(revision: envelope.revision, snapshotID: envelope.snapshotID,
                               protocolVersion: envelope.protocolVersion, components: envelope.components)
    }
}
