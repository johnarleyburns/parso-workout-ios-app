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

/// Durable, session-owned finalization watermark. `finalSequence` is
/// `unknownWatermark` until the Watch reports its last batch sequence, so
/// completion is impossible before the real watermark is known; an explicit
/// zero-measurement workout reports `finalSequence == 0` and completes.
public struct WatchHRFinalizationState: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case pending, complete, failedRecoverably }
    public static let unknownWatermark = Int.max

    public let sessionID: UUID
    public let captureEpoch: UUID
    public var finalSequence: Int
    public var receiptCursor: Int
    public var status: Status

    public init(sessionID: UUID, captureEpoch: UUID, finalSequence: Int = unknownWatermark,
                receiptCursor: Int = 0, status: Status = .pending) {
        self.sessionID = sessionID; self.captureEpoch = captureEpoch
        self.finalSequence = finalSequence; self.receiptCursor = receiptCursor; self.status = status
    }
    public var watermarkKnown: Bool { finalSequence != Self.unknownWatermark }
}

public enum WatchHRFinalizationError: Error, Equatable, Sendable {
    case pendingStateNotPersisted
}

public protocol WatchHeartRateFinalizationStore {
    func load(sessionID: UUID) -> WatchHRFinalizationState?
    func save(_ state: WatchHRFinalizationState) throws
    func clear(sessionID: UUID)
}

/// Process-local default; the app injects a persistent store.
public final class InMemoryWatchHeartRateFinalizationStore: WatchHeartRateFinalizationStore {
    private var states: [UUID: WatchHRFinalizationState] = [:]
    public init() {}
    public func load(sessionID: UUID) -> WatchHRFinalizationState? { states[sessionID] }
    public func save(_ state: WatchHRFinalizationState) throws { states[state.sessionID] = state }
    public func clear(sessionID: UUID) { states[sessionID] = nil }
}

public protocol WatchHeartRateReceiptStore {
    func load(sessionID: UUID) -> WatchHRReceiptState?
    func save(_ state: WatchHRReceiptState) throws
    func clear(sessionID: UUID)
}

/// Phone-side identity of a workout that may still receive Watch HR.
public struct WatchHRRoute: Equatable, Sendable {
    public var requestID: UUID
    public var captureEpoch: UUID
    public init(requestID: UUID, captureEpoch: UUID) { self.requestID = requestID; self.captureEpoch = captureEpoch }
}

public enum WatchHRReceiveOutcome: Equatable, Sendable {
    case accepted(count: Int)
    case duplicate
    /// Matched a cancelled preflight identity: acknowledged and dropped, never recorded.
    case tombstoned
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
    /// Returns the request ID and capture epoch bound to a workout that may
    /// still receive data (active or finished-pending), or nil if unknown.
    private let expectedRoute: (UUID) -> WatchHRRoute?
    /// Persists observations into the session; false means not durable.
    private let persist: (UUID, [WatchHRObservation]) -> Bool
    private let finalizationStore: WatchHeartRateFinalizationStore
    /// True when `(session, request, epoch)` was cancelled; such packets are ACKed and dropped.
    private let isTombstoned: (WatchHRMessage) -> Bool
    /// Fired exactly once per session when finalization first reaches complete.
    /// The app refreshes summary, History, This Week, watch snapshot and Health backup here.
    public var onFinalizationComplete: ((UUID) -> Void)?

    public init(store: WatchHeartRateReceiptStore, transport: WatchHeartRateTransport,
                finalizationStore: WatchHeartRateFinalizationStore = InMemoryWatchHeartRateFinalizationStore(),
                expectedRoute: @escaping (UUID) -> WatchHRRoute?,
                isTombstoned: @escaping (WatchHRMessage) -> Bool = { _ in false },
                persist: @escaping (UUID, [WatchHRObservation]) -> Bool) {
        self.store = store; self.transport = transport; self.finalizationStore = finalizationStore
        self.expectedRoute = expectedRoute; self.isTombstoned = isTombstoned; self.persist = persist
    }

    /// The pending/complete state for a session, or nil if none for this capture epoch.
    public func finalizationState(sessionID: UUID) -> WatchHRFinalizationState? {
        guard let state = finalizationStore.load(sessionID: sessionID),
              let route = expectedRoute(sessionID), route.captureEpoch == state.captureEpoch else { return nil }
        return state
    }

    /// True while a finished workout is still receiving Watch measurements
    /// (UI: "Receiving remaining Apple Watch measurements").
    public func isReceivingRemainingMeasurements(sessionID: UUID) -> Bool {
        guard let state = finalizationState(sessionID: sessionID) else { return false }
        return state.status != .complete
    }

    /// Advances the durable finalization state from the receipt journal; a throw
    /// means the caller must not acknowledge.
    private func advanceFinalization(sessionID: UUID, receipt: WatchHRReceiptState) throws {
        guard var fin = finalizationState(sessionID: sessionID), fin.status != .complete else { return }
        fin.receiptCursor = receipt.cursor
        if let final = receipt.finalSequence { fin.finalSequence = final }
        let wasComplete = fin.status == .complete
        fin.status = fin.watermarkKnown && fin.receiptCursor >= fin.finalSequence ? .complete : .pending
        try finalizationStore.save(fin)
        if fin.status == .complete && !wasComplete { onFinalizationComplete?(sessionID) }
    }

    @discardableResult
    public func handle(_ dictionary: [String: Any]) -> WatchHRReceiveOutcome {
        let message: WatchHRMessage
        switch WatchHRMessage.parse(dictionary) {
        case .failure(let reason): return reject(reason)
        case .success(let parsed): message = parsed
        }
        // Identity must match exactly before anything is persisted or acknowledged.
        guard let route = expectedRoute(message.phoneWorkoutSessionID) else {
            if message.kind != .finalizeRequest, isTombstoned(message) {
                acknowledge(message, cursor: message.sequence)
                return .tombstoned
            }
            return reject(.identityMismatch)
        }
        if let reason = message.validateScope(phoneWorkoutSessionID: message.phoneWorkoutSessionID,
                                              watchRequestID: route.requestID, captureEpoch: route.captureEpoch) {
            return reject(reason)
        }
        var state = store.load(sessionID: message.phoneWorkoutSessionID)
            ?? WatchHRReceiptState(phoneWorkoutSessionID: message.phoneWorkoutSessionID)
        switch message.kind {
        case .observations:
            guard message.acknowledgement == nil || !message.observations.isEmpty else { return reject(.emptyBatch) }
            if state.deliveryIDs.contains(message.deliveryID) || state.sequences.contains(message.sequence) {
                Self.log.debug("duplicate delivery")
                do { try advanceFinalization(sessionID: message.phoneWorkoutSessionID, receipt: state) } catch {
                    return .persistenceFailed
                }
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
            do { try advanceFinalization(sessionID: message.phoneWorkoutSessionID, receipt: state) } catch {
                Self.log.error("finalization save failed, not acknowledged")
                return .persistenceFailed
            }
            acknowledge(message, cursor: state.cursor)
            return .accepted(count: message.observations.count)
        case .finalizeAcknowledgement:
            state.finalSequence = message.sequence
            do {
                try store.save(state)
                try advanceFinalization(sessionID: message.phoneWorkoutSessionID, receipt: state)
            } catch { return .persistenceFailed }
            if state.finalizationComplete { acknowledge(message, cursor: state.cursor) }
            Self.log.info("finalization \(state.finalizationComplete ? "complete" : "pending", privacy: .public)")
            return .finalizationUpdated(complete: state.finalizationComplete)
        case .finalizeRequest:
            return reject(.malformed) // phone → Watch only
        }
    }

    /// Watch-started workout: `end_session` carried a transfer route and the final
    /// watermark. Registers the route, then finalizes once every chunk (possibly
    /// already received) is persisted. Throws if the pending state is not durable.
    public func registerCompletionTransfer(sessionID: UUID, transferID: UUID, captureEpoch: UUID,
                                           finalSequence: Int, addRoute: (WatchHRRoute) -> Void) throws {
        addRoute(WatchHRRoute(requestID: transferID, captureEpoch: captureEpoch))
        var fin = finalizationStore.load(sessionID: sessionID)
        if fin?.captureEpoch != captureEpoch { fin = WatchHRFinalizationState(sessionID: sessionID, captureEpoch: captureEpoch) }
        fin?.finalSequence = finalSequence
        if let fin { try finalizationStore.save(fin) }
        let receipt = store.load(sessionID: sessionID) ?? WatchHRReceiptState(phoneWorkoutSessionID: sessionID)
        var state = receipt
        state.finalSequence = finalSequence
        try store.save(state)
        try advanceFinalization(sessionID: sessionID, receipt: state)
    }

    /// Completion requires a durable finalization state; a receipt cursor alone never claims it.
    public func isFinalizationComplete(sessionID: UUID) -> Bool {
        finalizationState(sessionID: sessionID)?.status == .complete
    }

    /// True when the pending state could not be persisted; the user can Retry.
    public func isFinalizationFailedRecoverably(sessionID: UUID) -> Bool {
        finalizationState(sessionID: sessionID)?.status == .failedRecoverably
    }

    /// Retry action for a `failedRecoverably` finalization; same durable-first path.
    @discardableResult
    public func retryFinalization(sessionID: UUID, watchRequestID: UUID, captureEpoch: UUID,
                                  deliveryID: UUID = UUID()) -> Result<Void, WatchHRFinalizationError> {
        requestFinalization(sessionID: sessionID, watchRequestID: watchRequestID,
                            captureEpoch: captureEpoch, deliveryID: deliveryID)
    }

    /// Phone side of the finalize handshake: asks the Watch to flush. Durable pending
    /// state is saved BEFORE any transport; if that fails nothing is sent and the
    /// failure is recorded (best effort) as `failedRecoverably`.
    @discardableResult
    public func requestFinalization(sessionID: UUID, watchRequestID: UUID, captureEpoch: UUID,
                                    deliveryID: UUID = UUID()) -> Result<Void, WatchHRFinalizationError> {
        do {
            if var existing = finalizationStore.load(sessionID: sessionID), existing.captureEpoch == captureEpoch {
                if existing.status == .failedRecoverably {
                    existing.status = .pending
                    try finalizationStore.save(existing)
                }
            } else {
                try finalizationStore.save(WatchHRFinalizationState(sessionID: sessionID, captureEpoch: captureEpoch))
            }
        } catch {
            Self.log.error("pending finalization state not persisted; not sending")
            try? finalizationStore.save(WatchHRFinalizationState(sessionID: sessionID, captureEpoch: captureEpoch,
                                                                 status: .failedRecoverably))
            return .failure(.pendingStateNotPersisted)
        }
        let message = WatchHRMessage(kind: .finalizeRequest, deliveryID: deliveryID,
                                     phoneWorkoutSessionID: sessionID, watchRequestID: watchRequestID,
                                     captureEpoch: captureEpoch)
        if transport.isReachable { transport.sendImmediate(message) }
        transport.transferUserInfo(message)
        Self.log.info("finalization requested")
        return .success(())
    }

    /// Explicit user discard of one workout's receipt journal.
    public func discard(sessionID: UUID) {
        store.clear(sessionID: sessionID)
        finalizationStore.clear(sessionID: sessionID)
        Self.log.info("terminal discard")
    }

    private func acknowledge(_ message: WatchHRMessage, cursor: Int) {
        let ack = WatchHRMessage(kind: message.kind == .finalizeAcknowledgement ? .finalizeAcknowledgement : .observations,
                                 deliveryID: UUID(uuid: message.deliveryID.uuid),
                                 phoneWorkoutSessionID: message.phoneWorkoutSessionID,
                                 watchRequestID: message.watchRequestID, captureEpoch: message.captureEpoch,
                                 sequence: message.sequence,
                                 acknowledgement: WatchHRAcknowledgement(deliveryID: message.deliveryID, cursor: cursor))
        if transport.isReachable { transport.sendImmediate(ack) }
        transport.transferUserInfo(ack)
    }

    private func reject(_ reason: WatchHRMessageRejection) -> WatchHRReceiveOutcome {
        Self.log.error("rejected: \(reason.rawValue, privacy: .public)")
        return .rejected(reason)
    }
}
