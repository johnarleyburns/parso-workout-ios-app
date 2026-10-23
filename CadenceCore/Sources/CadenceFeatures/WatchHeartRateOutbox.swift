import Foundation
import OSLog

/// Persisted Watch-side journal for one phone-owned workout.
public struct WatchHeartRateOutboxState: Codable, Equatable, Sendable {
    public struct Batch: Codable, Equatable, Sendable {
        public var deliveryID: UUID
        public var sequence: Int
        public var observations: [WatchHRObservation]
        /// Last time this batch was handed to `transferUserInfo` (clock seconds).
        public var durableQueuedAt: TimeInterval?
    }
    public var phoneWorkoutSessionID: UUID
    public var watchRequestID: UUID
    /// Adopted from the phone's start command; stamped on every envelope.
    public var captureEpoch: UUID
    public var nextSequence = 1
    /// Observations accepted but not yet sealed into a batch.
    public var pending: [WatchHRObservation] = []
    public var batches: [Batch] = []
    /// Identities seen, so a later callback for the same sample never re-adds it.
    public var seenKeys: Set<String> = []
    public var finalizeRequested = false
    public var lastFinalizeAcknowledgedAt: TimeInterval?
    /// Earlier workouts whose data is not yet acknowledged. A new workout never
    /// erases them; they keep delivering to their own session until acknowledged
    /// or explicitly discarded (at most `maximumRetiredJournals`).
    public var retired: [WatchHeartRateOutboxState] = []
}

public protocol WatchHeartRateOutboxStore {
    func load() -> WatchHeartRateOutboxState?
    func save(_ state: WatchHeartRateOutboxState) throws
    func clear()
}

public protocol WatchHeartRateTransport {
    var isActivated: Bool { get }
    var isReachable: Bool { get }
    func sendImmediate(_ message: WatchHRMessage)
    func transferUserInfo(_ message: WatchHRMessage)
}

public enum WatchHeartRateRecordOutcome: Equatable, Sendable {
    case accepted, duplicate, rejected(WatchHRMessageRejection), notPersisted
}

/// Durable, idempotent Watch → phone heart-rate delivery.
///
/// Bounds (deterministic): at most `maximumBatchSize` observations per batch and
/// `maximumRetainedObservations` unacknowledged in total (24 000 ≈ 6.6 h at one
/// sample per second; HealthKit workouts deliver far fewer). If the bound is hit
/// while observations are still unsealed, adjacent unsealed pairs are merged
/// keeping the higher BPM (extrema and coverage kept, nothing invented). If
/// every retained observation is already sealed, new ones are refused loudly
/// (`failedRecoverably`) rather than dropping unacknowledged data.
@MainActor
public final class WatchHeartRateOutbox {
    public static let maximumBatchSize = 30
    public static let maximumRetainedObservations = 24_000
    /// Minimum gap before an unacknowledged batch is re-queued durably or resent.
    public static let maximumRetiredJournals = 4
    public static let retryInterval: TimeInterval = 60
    public static let minimumBPM = WatchHRMessage.minimumBPM
    public static let maximumBPM = WatchHRMessage.maximumBPM

    private static let log = Logger(subsystem: "guru.parso.cadence", category: "WatchHROutbox")

    private let store: WatchHeartRateOutboxStore
    private let transport: WatchHeartRateTransport
    private let clock: () -> TimeInterval
    private let makeUUID: () -> UUID
    public private(set) var state: WatchHeartRateOutboxState?
    public private(set) var failedRecoverably = false
    /// True while a new workout cannot be bound because retaining all earlier
    /// unacknowledged journals would exceed `maximumRetiredJournals`.
    public private(set) var bindingRefused = false
    private var lastImmediateAt: TimeInterval?
    /// Counts only; see `WatchHRTransportDiagnostics`.
    public private(set) var diagnostics = WatchHRTransportDiagnostics()

    public init(store: WatchHeartRateOutboxStore, transport: WatchHeartRateTransport,
                clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
                makeUUID: @escaping () -> UUID = UUID.init) {
        self.store = store; self.transport = transport; self.clock = clock; self.makeUUID = makeUUID
        self.state = store.load()
    }

    public var transportState: WatchHRTransportState {
        guard let state else { return .idle }
        if failedRecoverably { return .failedRecoverably }
        let outstanding = !state.pending.isEmpty || !state.batches.isEmpty
        if state.finalizeRequested { return outstanding ? .pendingDelivery : .awaitingFinalization }
        return .streaming
    }
    /// Last durable batch sequence once finalization was requested; nil before.
    public var finalSequence: Int? {
        guard let state, state.finalizeRequested else { return nil }
        return state.nextSequence - 1
    }
    public var unacknowledgedCount: Int {
        (state?.pending.count ?? 0) + (state?.batches.reduce(0) { $0 + $1.observations.count } ?? 0)
    }

    /// Scopes the journal to a phone-owned workout. Re-binding the same pair
    /// keeps the persisted state; a different pair replaces it.
    @discardableResult
    public func bind(phoneWorkoutSessionID: UUID, watchRequestID: UUID, captureEpoch: UUID) -> Bool {
        if let state, state.phoneWorkoutSessionID == phoneWorkoutSessionID, state.watchRequestID == watchRequestID,
           state.captureEpoch == captureEpoch { return true }
        var fresh = WatchHeartRateOutboxState(phoneWorkoutSessionID: phoneWorkoutSessionID, watchRequestID: watchRequestID,
                                              captureEpoch: captureEpoch)
        if var old = state {
            fresh.retired = old.retired
            old.retired = []
            if !(old.pending.isEmpty && old.batches.isEmpty) {
                // Backpressure: never drop unacknowledged data to make room.
                guard fresh.retired.count < Self.maximumRetiredJournals else {
                    bindingRefused = true
                    failedRecoverably = true
                    Self.log.error("retired journal limit reached, new workout not bound")
                    return false
                }
                sealPending(&old)
                fresh.retired.append(old)
                Self.log.info("earlier workout retained for delivery")
            }
        }
        state = fresh
        failedRecoverably = false
        bindingRefused = false
        persist()
        return true
    }

    @discardableResult
    public func record(bpm: Double, sampleEnd: Date, source: HeartRateObservationSource, sampleID: String? = nil) -> WatchHeartRateRecordOutcome {
        guard state != nil, !bindingRefused else { return .notPersisted }
        guard source == .watchHealthKit || source == .watchBLE else { return .rejected(.invalidSource) }
        guard bpm.isFinite, bpm >= Self.minimumBPM, bpm <= Self.maximumBPM else { return .rejected(.invalidBPM) }
        let end = sampleEnd.timeIntervalSince1970
        guard end.isFinite, end > 0 else { return .rejected(.invalidTimestamp) }
        let key = Self.key(source: source, sampleEnd: end, bpm: bpm, sampleID: sampleID)
        // Move the state out so the in-place mutation below never copies the arrays.
        guard var s = state else { return .notPersisted }
        state = nil
        defer { state = s }
        // The conservative key always applies, so a poll that discovered a
        // sample without identity and a builder callback that has it dedupe.
        let weak = Self.key(source: source, sampleEnd: end, bpm: bpm, sampleID: nil)
        if s.seenKeys.contains(key) || s.seenKeys.contains(weak) {
            Self.log.debug("observation deduplicated")
            return .duplicate
        }
        if s.pending.count + s.batches.reduce(0, { $0 + $1.observations.count }) >= Self.maximumRetainedObservations {
            guard compactPending(&s) else {
                failedRecoverably = true
                Self.log.error("outbox full, observation refused")
                return .notPersisted
            }
        }
        s.seenKeys.insert(key)
        if sampleID != nil { s.seenKeys.insert(weak) }
        s.pending.append(WatchHRObservation(observationID: makeUUID(), source: source, sampleEnd: end, bpm: bpm, sampleID: sampleID))
        state = s
        guard persist() else { return .notPersisted }
        Self.log.debug("observation accepted")
        return .accepted
    }

    /// Journals a finished workout's complete series in one durable write, seals
    /// it into budgeted chunks and marks the journal final. Nothing is delivered
    /// here (the caller sends its own message first, then `flush()`). Returns the
    /// final batch sequence (0 when nothing was valid) or nil when it could not be
    /// persisted; every chunk stays retained until the phone acknowledges it.
    public func sealCompletion(_ points: [(bpm: Double, sampleEnd: TimeInterval)]) -> Int? {
        guard var s = state, !bindingRefused else { return nil }
        state = nil
        defer { state = s }
        for p in points {
            guard p.bpm.isFinite, p.bpm >= Self.minimumBPM, p.bpm <= Self.maximumBPM,
                  p.sampleEnd.isFinite, p.sampleEnd > 0 else { continue }
            let key = Self.key(source: .watchHealthKit, sampleEnd: p.sampleEnd, bpm: p.bpm, sampleID: nil)
            guard s.seenKeys.insert(key).inserted else { continue }
            s.pending.append(WatchHRObservation(observationID: makeUUID(), source: .watchHealthKit,
                                                sampleEnd: p.sampleEnd, bpm: p.bpm))
        }
        s.finalizeRequested = true
        sealPending(&s)
        state = s
        guard persist() else { return nil }
        return s.nextSequence - 1
    }

    /// Seals pending observations and attempts delivery. Observations are
    /// always persisted before this runs.
    public func flush() {
        guard var s = state, transport.isActivated else { return }
        sealPending(&s)
        state = s
        guard persist() else { return }
        deliver()
    }

    /// Re-attempts unacknowledged batches (activation, reachability recovery,
    /// bounded timer). Nothing is sent more often than `retryInterval`, except
    /// batches never handed over yet.
    public func retry(reason: String) {
        guard var s = state, transport.isActivated else { return }
        sealPending(&s)
        state = s
        persist()
        diagnostics.retryCount += 1
        Self.log.info("retry: \(reason, privacy: .public), unacknowledged chunks \(s.batches.count)")
        deliver()
    }

    private func deliver() {
        guard var s = state else { return }
        let now = clock()
        var changed = deliver(&s, now: now)
        for i in s.retired.indices { changed = deliver(&s.retired[i], now: now) || changed }
        if transport.isReachable { lastImmediateAt = now }
        state = s
        if changed { persist() }
    }

    private func deliver(_ s: inout WatchHeartRateOutboxState, now: TimeInterval) -> Bool {
        var changed = false
        let chunker = WatchHRChunker(phoneWorkoutSessionID: s.phoneWorkoutSessionID, watchRequestID: s.watchRequestID,
                                     captureEpoch: s.captureEpoch)
        for i in s.batches.indices {
            let batch = s.batches[i]
            // An unencodable/oversized chunk stays in the outbox (never dropped or truncated).
            let bytes = chunker.encodedSize(batch.observations)
            if bytes > WatchHRChunker.maxEncodedBytes {
                diagnostics.oversizedChunkCount += 1
                failedRecoverably = true
                Self.log.error("chunk exceeds byte budget, retained")
                continue
            }
            diagnostics.largestChunkBytes = max(diagnostics.largestChunkBytes, bytes)
            let message = WatchHRMessage(kind: .observations, deliveryID: batch.deliveryID,
                                         phoneWorkoutSessionID: s.phoneWorkoutSessionID,
                                         watchRequestID: s.watchRequestID, captureEpoch: s.captureEpoch,
                                         sequence: batch.sequence,
                                         observations: batch.observations)
            let due = batch.durableQueuedAt.map { now - $0 >= Self.retryInterval } ?? true
            if transport.isReachable && (due || lastImmediateAt.map { now - $0 >= Self.retryInterval } ?? true) {
                transport.sendImmediate(message)
                Self.log.debug("immediate attempt")
            } else if !transport.isReachable {
                Self.log.debug("immediate skipped: unreachable")
            }
            if due {
                transport.transferUserInfo(message)
                s.batches[i].durableQueuedAt = now
                changed = true
                Self.log.debug("durable transfer queued")
            }
        }
        return changed
    }

    /// Runs `body` on the journal (current or retired) that owns this scope.
    private func withJournal<T>(sessionID: UUID, requestID: UUID, captureEpoch: UUID,
                                _ body: (inout WatchHeartRateOutboxState) -> T) -> T? {
        guard var s = state else { return nil }
        state = nil
        defer { state = s }
        if s.phoneWorkoutSessionID == sessionID, s.watchRequestID == requestID, s.captureEpoch == captureEpoch { return body(&s) }
        guard let i = s.retired.firstIndex(where: { $0.phoneWorkoutSessionID == sessionID && $0.watchRequestID == requestID
            && $0.captureEpoch == captureEpoch })
        else { return nil }
        let result = body(&s.retired[i])
        if s.retired[i].batches.isEmpty && s.retired[i].pending.isEmpty {
            s.retired.remove(at: i)
        }
        return result
    }

    /// Applies an acknowledgement. Returns false when it is for another
    /// workout (untouched) or structurally invalid.
    @discardableResult
    public func handleAcknowledgement(_ message: WatchHRMessage) -> Bool {
        guard message.structuralRejection == nil, let ack = message.acknowledgement,
              withJournal(sessionID: message.phoneWorkoutSessionID, requestID: message.watchRequestID, captureEpoch: message.captureEpoch, { (s: inout WatchHeartRateOutboxState) -> Bool in
                  s.batches.removeAll { $0.deliveryID == ack.deliveryID || $0.sequence <= ack.cursor }
                  return true
              }) != nil else {
            Self.log.error("acknowledgement rejected")
            return false
        }
        persist()
        diagnostics.receiptCount += 1
        Self.log.info("acknowledgement accepted")
        if message.kind == .finalizeAcknowledgement { releaseIfFullyDelivered() }
        return true
    }

    /// Phone asked to finish. Flushes everything and, once every batch has been
    /// persisted here and handed to WatchConnectivity, sends the final
    /// acknowledgement. The journal is retained until the phone acknowledges.
    /// Returns false if the request is for a different workout or not yet safe.
    @discardableResult
    public func handleFinalizeRequest(_ message: WatchHRMessage) -> Bool {
        guard message.kind == .finalizeRequest, message.structuralRejection == nil, transport.isActivated,
              let lastSequence = withJournal(sessionID: message.phoneWorkoutSessionID,
                                             requestID: message.watchRequestID,
                                             captureEpoch: message.captureEpoch, { s -> Int in
                  s.finalizeRequested = true
                  sealPending(&s)
                  for i in s.batches.indices { s.batches[i].durableQueuedAt = nil }
                  return s.nextSequence - 1
              }) else {
            Self.log.error("finalize request rejected or deferred")
            return false
        }
        Self.log.info("finalization requested")
        guard persist() else { return false }
        deliver() // persisted first; hands every batch to WatchConnectivity
        let handedOver = withJournal(sessionID: message.phoneWorkoutSessionID, requestID: message.watchRequestID,
                                 captureEpoch: message.captureEpoch) {
            $0.batches.allSatisfy { $0.durableQueuedAt != nil }
        } ?? true
        guard handedOver else { return false }
        let final = WatchHRMessage(kind: .finalizeAcknowledgement, deliveryID: makeUUID(),
                                   phoneWorkoutSessionID: message.phoneWorkoutSessionID,
                                   watchRequestID: message.watchRequestID, captureEpoch: message.captureEpoch,
                                   sequence: lastSequence)
        if transport.isReachable { transport.sendImmediate(final) }
        transport.transferUserInfo(final)
        Self.log.info("finalization complete")
        return true
    }

    /// Explicit, user-confirmed discard of one workout's journal. A different
    /// workout's state is never touched.
    @discardableResult
    public func discard(phoneWorkoutSessionID: UUID) -> Bool {
        guard var s = state else { return false }
        if s.phoneWorkoutSessionID == phoneWorkoutSessionID {
            if s.retired.isEmpty { state = nil; store.clear() } else {
                var next = s.retired.removeLast()
                next.retired = s.retired
                state = next
                persist()
            }
        } else if let i = s.retired.firstIndex(where: { $0.phoneWorkoutSessionID == phoneWorkoutSessionID }) {
            s.retired.remove(at: i)
            state = s
            persist()
        } else { return false }
        failedRecoverably = false
        Self.log.info("terminal discard")
        return true
    }

    /// Drops journals the phone fully confirmed (all batches acknowledged and
    /// finalization answered). A still-needed journal is never touched.
    public func releaseIfFullyDelivered() {
        guard var s = state else { return }
        s.retired.removeAll { $0.pending.isEmpty && $0.batches.isEmpty }
        if s.finalizeRequested, s.pending.isEmpty, s.batches.isEmpty {
            if s.retired.isEmpty { state = nil; store.clear(); return }
            var next = s.retired.removeLast(); next.retired = s.retired
            s = next
        }
        state = s
        persist()
    }

    // MARK: - Helpers

    private func sealPending(_ s: inout WatchHeartRateOutboxState) {
        guard !s.pending.isEmpty else { return }
        s.pending.sort { $0.sampleEnd < $1.sampleEnd }
        let chunker = WatchHRChunker(phoneWorkoutSessionID: s.phoneWorkoutSessionID, watchRequestID: s.watchRequestID,
                                     captureEpoch: s.captureEpoch)
        let chunks = chunker.chunks(s.pending)
        s.pending = []
        diagnostics.observationCount += chunks.reduce(0) { $0 + $1.count }
        diagnostics.chunkCount += chunks.count
        for chunk in chunks {
            s.batches.append(.init(deliveryID: makeUUID(), sequence: s.nextSequence, observations: chunk, durableQueuedAt: nil))
            s.nextSequence += 1
        }
    }

    private func compactPending(_ s: inout WatchHeartRateOutboxState) -> Bool {
        guard s.pending.count >= 2 else { return false }
        var out: [WatchHRObservation] = []
        var i = 0
        let sorted = s.pending.sorted { $0.sampleEnd < $1.sampleEnd }
        while i < sorted.count {
            if i + 1 < sorted.count { out.append(sorted[i].bpm >= sorted[i + 1].bpm ? sorted[i] : sorted[i + 1]) } else { out.append(sorted[i]) }
            i += 2
        }
        s.pending = out
        return true
    }

    @discardableResult
    private func persist() -> Bool {
        guard let state else { return true }
        do { try store.save(state); Self.log.debug("outbox persisted"); return true } catch {
            failedRecoverably = true
            Self.log.error("outbox persistence failed")
            return false
        }
    }

    nonisolated static func key(source: HeartRateObservationSource, sampleEnd: TimeInterval, bpm: Double, sampleID: String?) -> String {
        if let sampleID { return "id:\(sampleID)" }
        return "\(source.rawValue)|\(Int((sampleEnd * 1000).rounded()))|\(Int(bpm.rounded()))"
    }
}
