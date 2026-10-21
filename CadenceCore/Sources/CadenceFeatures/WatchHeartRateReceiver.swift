import Foundation
import OSLog

/// What the phone durably remembers about one workout's received Watch HR.
public struct WatchHRReceiptState: Codable, Equatable, Sendable {
    public var phoneWorkoutSessionID: UUID
    public var deliveryIDs: Set<UUID> = []
    public var sequences: Set<Int> = []
    public var finalSequence: Int?

    /// Highest n such that batches 1...n were all persisted.
    public var cursor: Int {
        var n = 0
        while sequences.contains(n + 1) { n += 1 }
        return n
    }
    public var finalizationComplete: Bool { finalSequence.map { cursor >= $0 } ?? false }
}

public protocol WatchHeartRateReceiptStore {
    func load(sessionID: UUID) -> WatchHRReceiptState?
    func save(_ state: WatchHRReceiptState) throws
    func clear(sessionID: UUID)
}

public enum WatchHRReceiveOutcome: Equatable, Sendable {
    case accepted(count: Int)
    case duplicate
    case finalizationUpdated(complete: Bool)
    case rejected(WatchHRMessageRejection)
    /// Not acknowledged; the Watch keeps the batch and retries.
    case persistenceFailed
}

/// Phone-side receiver: validates before touching UI or storage, routes only to
/// the matching active or retained-finished workout, persists through the
/// session-owned HR path, and acknowledges only after persistence succeeds.
@MainActor
public final class WatchHeartRateReceiver {
    private static let log = Logger(subsystem: "guru.parso.cadence", category: "WatchHRReceiver")

    private let store: WatchHeartRateReceiptStore
    private let transport: WatchHeartRateTransport
    /// Returns the Watch request ID bound to a workout that may still receive
    /// data (active or finished-pending), or nil if the workout is unknown.
    private let expectedRequestID: (UUID) -> UUID?
    /// Persists observations into the session; false means not durable.
    private let persist: (UUID, [WatchHRObservation]) -> Bool

    public init(store: WatchHeartRateReceiptStore, transport: WatchHeartRateTransport,
                expectedRequestID: @escaping (UUID) -> UUID?,
                persist: @escaping (UUID, [WatchHRObservation]) -> Bool) {
        self.store = store; self.transport = transport
        self.expectedRequestID = expectedRequestID; self.persist = persist
    }

    @discardableResult
    public func handle(_ dictionary: [String: Any]) -> WatchHRReceiveOutcome {
        let message: WatchHRMessage
        switch WatchHRMessage.parse(dictionary) {
        case .failure(let reason): return reject(reason)
        case .success(let parsed): message = parsed
        }
        guard let request = expectedRequestID(message.phoneWorkoutSessionID) else { return reject(.sessionMismatch) }
        if let reason = message.validateScope(phoneWorkoutSessionID: message.phoneWorkoutSessionID, watchRequestID: request) {
            return reject(reason)
        }
        var state = store.load(sessionID: message.phoneWorkoutSessionID)
            ?? WatchHRReceiptState(phoneWorkoutSessionID: message.phoneWorkoutSessionID)
        switch message.kind {
        case .observations:
            guard message.acknowledgement == nil || !message.observations.isEmpty else { return reject(.emptyBatch) }
            if state.deliveryIDs.contains(message.deliveryID) || state.sequences.contains(message.sequence) {
                Self.log.debug("duplicate delivery")
                acknowledge(message, cursor: state.cursor)
                return .duplicate
            }
            guard persist(message.phoneWorkoutSessionID, message.observations) else {
                Self.log.error("persistence failed, not acknowledged")
                return .persistenceFailed
            }
            state.deliveryIDs.insert(message.deliveryID)
            state.sequences.insert(message.sequence)
            // ACK means observations AND receipt state are durable. If the receipt
            // save fails nothing is acknowledged; the Watch retains the batch and
            // the replay re-persists idempotently (the recorder dedupes by identity/time).
            do { try store.save(state) } catch {
                Self.log.error("receipt journal save failed, not acknowledged")
                return .persistenceFailed
            }
            acknowledge(message, cursor: state.cursor)
            return .accepted(count: message.observations.count)
        case .finalizeAcknowledgement:
            state.finalSequence = message.sequence
            do { try store.save(state) } catch { return .persistenceFailed }
            if state.finalizationComplete { acknowledge(message, cursor: state.cursor) }
            Self.log.info("finalization \(state.finalizationComplete ? "complete" : "pending", privacy: .public)")
            return .finalizationUpdated(complete: state.finalizationComplete)
        case .finalizeRequest:
            return reject(.malformed) // phone → Watch only
        }
    }

    public func isFinalizationComplete(sessionID: UUID) -> Bool {
        store.load(sessionID: sessionID)?.finalizationComplete ?? false
    }

    /// Phone side of the finalize handshake: asks the Watch to flush.
    public func requestFinalization(sessionID: UUID, watchRequestID: UUID, deliveryID: UUID = UUID()) {
        let message = WatchHRMessage(kind: .finalizeRequest, deliveryID: deliveryID,
                                     phoneWorkoutSessionID: sessionID, watchRequestID: watchRequestID)
        if transport.isReachable { transport.sendImmediate(message) }
        transport.transferUserInfo(message)
        Self.log.info("finalization requested")
    }

    /// Explicit user discard of one workout's receipt journal.
    public func discard(sessionID: UUID) {
        store.clear(sessionID: sessionID)
        Self.log.info("terminal discard")
    }

    private func acknowledge(_ message: WatchHRMessage, cursor: Int) {
        let ack = WatchHRMessage(kind: message.kind == .finalizeAcknowledgement ? .finalizeAcknowledgement : .observations,
                                 deliveryID: UUID(uuid: message.deliveryID.uuid),
                                 phoneWorkoutSessionID: message.phoneWorkoutSessionID,
                                 watchRequestID: message.watchRequestID, sequence: message.sequence,
                                 acknowledgement: WatchHRAcknowledgement(deliveryID: message.deliveryID, cursor: cursor))
        if transport.isReachable { transport.sendImmediate(ack) }
        transport.transferUserInfo(ack)
    }

    private func reject(_ reason: WatchHRMessageRejection) -> WatchHRReceiveOutcome {
        Self.log.error("rejected: \(reason.rawValue, privacy: .public)")
        return .rejected(reason)
    }
}
