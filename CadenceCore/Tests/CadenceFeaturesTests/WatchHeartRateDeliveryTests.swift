import Testing
import Foundation
@testable import CadenceFeatures

final class FakeHRStore: WatchHeartRateOutboxStore {
    var saved: WatchHeartRateOutboxState?
    var saveCount = 0
    var events: [String] = []
    func load() -> WatchHeartRateOutboxState? { saved }
    func save(_ state: WatchHeartRateOutboxState) throws { saved = state; saveCount += 1; events.append("save") }
    func clear() { saved = nil }
}

final class FakeHRTransport: WatchHeartRateTransport {
    var isActivated = true
    var isReachable = true
    var immediate: [WatchHRMessage] = []
    var durable: [WatchHRMessage] = []
    weak var store: FakeHRStore?
    func sendImmediate(_ message: WatchHRMessage) { store?.events.append("immediate"); immediate.append(message) }
    func transferUserInfo(_ message: WatchHRMessage) { store?.events.append("durable"); durable.append(message) }
}

final class FakeReceiptStore: WatchHeartRateReceiptStore {
    var states: [UUID: WatchHRReceiptState] = [:]
    func load(sessionID: UUID) -> WatchHRReceiptState? { states[sessionID] }
    func save(_ state: WatchHRReceiptState) throws { states[state.phoneWorkoutSessionID] = state }
    func clear(sessionID: UUID) { states[sessionID] = nil }
}

@MainActor
struct WatchHeartRateDeliveryTests {
    let session = UUID(), request = UUID()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    final class Counter { var n: UInt32 = 0 }

    func makeOutbox(store: FakeHRStore = FakeHRStore(), transport: FakeHRTransport = FakeHRTransport(),
                    clock: @escaping () -> TimeInterval = { 1_800_000_100 }) -> (WatchHeartRateOutbox, FakeHRStore, FakeHRTransport) {
        transport.store = store
        let counter = Counter()
        let outbox = WatchHeartRateOutbox(store: store, transport: transport, clock: clock, makeUUID: {
            counter.n += 1
            return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", counter.n))!
        })
        outbox.bind(phoneWorkoutSessionID: session, watchRequestID: request)
        return (outbox, store, transport)
    }

    @MainActor final class Phone {
        let receipts = FakeReceiptStore()
        let transport = FakeHRTransport()
        var persisted: [UUID: [WatchHRObservation]] = [:]
        var failPersist = false
        var known: [UUID: UUID]
        var receiver: WatchHeartRateReceiver!
        init(known: [UUID: UUID]) {
            self.known = known
            receiver = WatchHeartRateReceiver(store: receipts, transport: transport,
                expectedRequestID: { [unowned self] in self.known[$0] },
                persist: { [unowned self] id, obs in
                    if self.failPersist { return false }
                    self.persisted[id, default: []] += obs; return true })
        }
    }

    @Test func samplePersistedBeforeAnyTransportAttempt() {
        let (outbox, store, _) = makeOutbox()
        outbox.record(bpm: 120, sampleEnd: t0, source: .watchHealthKit)
        outbox.flush()
        let firstTransport = store.events.firstIndex { $0 == "immediate" || $0 == "durable" }!
        #expect(store.events[..<firstTransport].contains("save"))
        #expect(store.saved?.pending.count == 1 || store.saved?.batches.count == 1)
    }

    @Test func immediateSendWithoutAckKeepsSampleAndAckRemovesExactlyThatBatch() {
        let (outbox, _, transport) = makeOutbox()
        outbox.record(bpm: 120, sampleEnd: t0, source: .watchHealthKit)
        outbox.flush()
        #expect(transport.immediate.count == 1)
        #expect(outbox.unacknowledgedCount == 1)
        // later second batch
        outbox.record(bpm: 125, sampleEnd: t0.addingTimeInterval(5), source: .watchHealthKit)
        outbox.flush()
        let first = transport.immediate[0]
        let ack = WatchHRMessage(kind: .observations, deliveryID: UUID(), phoneWorkoutSessionID: session,
                                 watchRequestID: request, acknowledgement: .init(deliveryID: first.deliveryID, cursor: 0))
        #expect(outbox.handleAcknowledgement(ack))
        #expect(outbox.unacknowledgedCount == 1)
        #expect(outbox.state?.batches.first?.sequence == 2)
    }

    @Test func unreachableStillQueuesDurablyAndReachabilityFlushesWithoutDuplicateDurable() {
        var now: TimeInterval = 1_800_000_100
        let (outbox, _, transport) = makeOutbox(transport: { let t = FakeHRTransport(); t.isReachable = false; return t }(), clock: { now })
        outbox.record(bpm: 120, sampleEnd: t0, source: .watchHealthKit)
        outbox.flush()
        #expect(transport.durable.count == 1)
        #expect(transport.immediate.isEmpty)
        transport.isReachable = true
        now += 5
        outbox.retry(reason: "reachability")
        #expect(transport.immediate.count == 1)
        #expect(transport.durable.count == 1) // not re-queued inside the retry interval
    }

    @Test func processRecreationResumesUnacknowledgedExactlyOnce() {
        let (outbox, store, transport) = makeOutbox(transport: { let t = FakeHRTransport(); t.isReachable = false; return t }())
        outbox.record(bpm: 120, sampleEnd: t0, source: .watchHealthKit)
        _ = transport
        let transport2 = FakeHRTransport(); transport2.store = store
        let revived = WatchHeartRateOutbox(store: store, transport: transport2, clock: { 1_800_000_100 })
        #expect(revived.unacknowledgedCount == 1)
        revived.flush()
        revived.flush()
        #expect(transport2.durable.count == 1)
        #expect(transport2.durable[0].observations.count == 1)
    }

    @Test func duplicateAndReorderedDeliveriesPersistOnce() {
        let (outbox, _, transport) = makeOutbox()
        outbox.record(bpm: 120, sampleEnd: t0, source: .watchHealthKit)
        outbox.flush()
        outbox.record(bpm: 121, sampleEnd: t0.addingTimeInterval(5), source: .watchHealthKit)
        outbox.flush()
        let phone = Phone(known: [session: request])
        let m1 = transport.immediate[0].payload, m2 = transport.immediate[1].payload
        #expect(phone.receiver.handle(m2) == .accepted(count: 1))
        #expect(phone.receiver.handle(m1) == .accepted(count: 1))
        #expect(phone.receiver.handle(m1) == .duplicate)
        #expect(phone.receiver.handle(transport.durable[1].payload) == .duplicate)
        #expect(phone.persisted[session]?.count == 2)
        let acks = Set(phone.transport.durable.compactMap { $0.acknowledgement?.deliveryID })
        #expect(acks.count == 2)
        // reordered: after m2 alone cursor must be 0
        #expect(phone.transport.durable[0].acknowledgement?.cursor == 0)
        #expect(phone.transport.durable[1].acknowledgement?.cursor == 2)
    }

    @Test func builderCallbackAfterPollDeduplicates() {
        let (outbox, _, _) = makeOutbox()
        #expect(outbox.record(bpm: 120, sampleEnd: t0, source: .watchHealthKit) == .accepted)
        #expect(outbox.record(bpm: 120, sampleEnd: t0, source: .watchHealthKit, sampleID: "HK-1") == .duplicate)
        #expect(outbox.unacknowledgedCount == 1)
    }

    @Test func repeatedHeartbeatDoesNotCreateObservations() {
        let (outbox, _, transport) = makeOutbox()
        outbox.record(bpm: 120, sampleEnd: t0, source: .watchHealthKit)
        for _ in 0..<5 { #expect(outbox.record(bpm: 120, sampleEnd: t0, source: .watchHealthKit) == .duplicate) }
        outbox.flush()
        #expect(transport.durable.count == 1)
        #expect(transport.durable[0].observations.count == 1)
    }

    @Test func invalidMessagesAreRejectedWithoutAcknowledgement() {
        let phone = Phone(known: [session: request])
        let good = WatchHRObservation(observationID: UUID(), source: .watchHealthKit, sampleEnd: t0.timeIntervalSince1970, bpm: 110)
        func msg(_ edit: (inout WatchHRMessage) -> Void) -> [String: Any] {
            var m = WatchHRMessage(kind: .observations, deliveryID: UUID(), phoneWorkoutSessionID: session,
                                   watchRequestID: request, sequence: 1, observations: [good])
            edit(&m); return m.payload
        }
        #expect(phone.receiver.handle(msg { $0.observations[0].bpm = 400 }) == .rejected(.invalidBPM))
        #expect(phone.receiver.handle(msg { $0.observations[0].sampleEnd = 0 }) == .rejected(.invalidTimestamp))
        #expect(phone.receiver.handle(msg { $0.version = 9 }) == .rejected(.unsupportedVersion))
        #expect(phone.receiver.handle(msg { $0.phoneWorkoutSessionID = UUID() }) == .rejected(.sessionMismatch))
        #expect(phone.receiver.handle(msg { $0.watchRequestID = UUID() }) == .rejected(.requestMismatch))
        #expect(phone.receiver.handle(["watchHRv1": Data([1, 2])]) == .rejected(.malformed))
        #expect(phone.persisted.isEmpty)
        #expect(phone.transport.durable.isEmpty && phone.transport.immediate.isEmpty)
        #expect(phone.receipts.states.isEmpty)
    }

    @Test func persistenceFailureIsNotAcknowledged() {
        let phone = Phone(known: [session: request])
        phone.failPersist = true
        let (outbox, _, transport) = makeOutbox()
        outbox.record(bpm: 120, sampleEnd: t0, source: .watchHealthKit)
        outbox.flush()
        #expect(phone.receiver.handle(transport.immediate[0].payload) == .persistenceFailed)
        #expect(phone.transport.durable.isEmpty)
        phone.failPersist = false
        #expect(phone.receiver.handle(transport.durable[0].payload) == .accepted(count: 1))
    }

    @Test func delayedWorkoutABatchCannotModifyWorkoutB() {
        let (outbox, _, transport) = makeOutbox()
        outbox.record(bpm: 120, sampleEnd: t0, source: .watchHealthKit)
        outbox.flush()
        let sessionB = UUID(), requestB = UUID()
        let phone = Phone(known: [sessionB: requestB]) // A is no longer known
        #expect(phone.receiver.handle(transport.durable[0].payload) == .rejected(.sessionMismatch))
        #expect(phone.persisted[sessionB] == nil)
        // Watch side: B-scoped ack must not touch A's batches
        let bAck = WatchHRMessage(kind: .observations, deliveryID: UUID(), phoneWorkoutSessionID: sessionB,
                                  watchRequestID: requestB,
                                  acknowledgement: .init(deliveryID: transport.durable[0].deliveryID, cursor: 5))
        #expect(!outbox.handleAcknowledgement(bAck))
        #expect(outbox.unacknowledgedCount == 1)
    }

    @Test func finishFinalizesRetainsUntilAckAndLateBatchMergesOnce() {
        let (outbox, _, transport) = makeOutbox(transport: { let t = FakeHRTransport(); t.isReachable = false; return t }())
        outbox.record(bpm: 120, sampleEnd: t0, source: .watchHealthKit)
        let phone = Phone(known: [session: request])
        phone.receiver.requestFinalization(sessionID: session, watchRequestID: request)
        let req = phone.transport.durable[0]
        #expect(outbox.handleFinalizeRequest(req))
        #expect(outbox.unacknowledgedCount == 1) // retained until acknowledged
        #expect(outbox.transportState == .pendingDelivery)
        let final = transport.durable.last!
        #expect(final.kind == .finalizeAcknowledgement && final.sequence == 1)
        // finalize ack arrives first: still pending, nothing false-complete
        #expect(phone.receiver.handle(final.payload) == .finalizationUpdated(complete: false))
        #expect(!phone.receiver.isFinalizationComplete(sessionID: session))
        // late batch merges once into the retained session
        #expect(phone.receiver.handle(transport.durable[0].payload) == .accepted(count: 1))
        #expect(phone.receiver.handle(transport.durable[0].payload) == .duplicate)
        #expect(phone.persisted[session]?.count == 1)
        #expect(phone.receiver.handle(final.payload) == .finalizationUpdated(complete: true))
        // phone acks flow back, watch releases journal
        for ack in phone.transport.durable where ack.acknowledgement != nil { outbox.handleAcknowledgement(ack) }
        #expect(outbox.state == nil)
    }

    @Test func discardOnlyClearsItsOwnScope() {
        let (outbox, store, _) = makeOutbox()
        outbox.record(bpm: 120, sampleEnd: t0, source: .watchHealthKit)
        #expect(!outbox.discard(phoneWorkoutSessionID: UUID()))
        #expect(store.saved != nil)
        #expect(outbox.discard(phoneWorkoutSessionID: session))
        #expect(store.saved == nil)
        let phone = Phone(known: [:])
        let other = UUID()
        phone.receipts.states[other] = WatchHRReceiptState(phoneWorkoutSessionID: other)
        phone.receiver.discard(sessionID: session)
        #expect(phone.receipts.states[other] != nil)
    }

    @Test func transportStateIsNotLiveFromHeartbeat() {
        let (outbox, _, _) = makeOutbox()
        #expect(outbox.transportState == .streaming)
        let idle = WatchHeartRateOutbox(store: FakeHRStore(), transport: FakeHRTransport())
        #expect(idle.transportState == .idle)
    }

    @Test func boundedRetentionCompactsPendingWithoutDroppingSealed() {
        let (outbox, _, _) = makeOutbox()
        for i in 0..<WatchHeartRateOutbox.maximumRetainedObservations {
            outbox.record(bpm: 100 + Double(i % 50), sampleEnd: t0.addingTimeInterval(Double(i)), source: .watchHealthKit)
        }
        #expect(outbox.unacknowledgedCount == WatchHeartRateOutbox.maximumRetainedObservations)
        #expect(outbox.record(bpm: 150, sampleEnd: t0.addingTimeInterval(99_999), source: .watchHealthKit) == .accepted)
        #expect(outbox.unacknowledgedCount < WatchHeartRateOutbox.maximumRetainedObservations)
    }
}

@MainActor
struct WatchHeartRateRetiredJournalTests {
    @Test func secondWorkoutKeepsFirstWorkoutsUnacknowledgedDataDeliverable() {
        let store = FakeHRStore(), transport = FakeHRTransport()
        transport.isReachable = false
        let outbox = WatchHeartRateOutbox(store: store, transport: transport, clock: { 1_800_000_100 })
        let a = UUID(), ra = UUID(), b = UUID(), rb = UUID()
        outbox.bind(phoneWorkoutSessionID: a, watchRequestID: ra)
        outbox.record(bpm: 120, sampleEnd: Date(timeIntervalSince1970: 1_800_000_000), source: .watchHealthKit)
        outbox.bind(phoneWorkoutSessionID: b, watchRequestID: rb)
        outbox.record(bpm: 90, sampleEnd: Date(timeIntervalSince1970: 1_800_000_500), source: .watchHealthKit)
        outbox.flush()
        let sessions = Set(transport.durable.map(\.phoneWorkoutSessionID))
        #expect(sessions == [a, b])
        // acknowledging A leaves B untouched
        let batchA = transport.durable.first { $0.phoneWorkoutSessionID == a }!
        let ack = WatchHRMessage(kind: .observations, deliveryID: UUID(), phoneWorkoutSessionID: a, watchRequestID: ra,
                                 acknowledgement: .init(deliveryID: batchA.deliveryID, cursor: 1))
        #expect(outbox.handleAcknowledgement(ack))
        #expect(outbox.state?.phoneWorkoutSessionID == b)
        #expect(outbox.unacknowledgedCount == 1)
        #expect(outbox.state?.retired.isEmpty == true)
    }
}

struct WatchHeartRateCommandCompatibilityTests {
    @Test func startCommandCarriesPhoneSessionIDAndLegacyOmitsIt() {
        let id = UUID(), req = UUID()
        let command = WatchHRCommand(action: .start, requestID: req, workoutType: "traditionalStrengthTraining",
                                     issuedAt: 5, phoneWorkoutSessionID: id)
        #expect(WatchHRCommand(payload: command.payload)?.phoneWorkoutSessionID == id)
        let legacy = WatchHRCommand(action: .start, requestID: req, issuedAt: 5)
        #expect(legacy.payload["phoneWorkoutSessionID"] == nil)
        #expect(WatchHRCommand(payload: legacy.payload)?.phoneWorkoutSessionID == nil)
    }
}

@MainActor
struct WatchHeartRateTransactionalDeliveryTests {
    final class FailingReceiptStore: WatchHeartRateReceiptStore {
        var states: [UUID: WatchHRReceiptState] = [:]
        var failSaves = true
        struct Boom: Error {}
        func load(sessionID: UUID) -> WatchHRReceiptState? { states[sessionID] }
        func save(_ state: WatchHRReceiptState) throws {
            if failSaves { throw Boom() }
            states[state.phoneWorkoutSessionID] = state
        }
        func clear(sessionID: UUID) { states[sessionID] = nil }
    }

    @Test func receiptSaveFailureSendsNoAckAndReplayIsAcknowledged() {
        let session = UUID(), request = UUID()
        let store = FailingReceiptStore(), transport = FakeHRTransport()
        var persisted = 0
        let receiver = WatchHeartRateReceiver(store: store, transport: transport,
                                              expectedRequestID: { _ in request },
                                              persist: { _, _ in persisted += 1; return true })
        let obs = WatchHRObservation(observationID: UUID(), source: .watchHealthKit,
                                     sampleEnd: 1_800_000_000, bpm: 120, sampleID: nil)
        let message = WatchHRMessage(kind: .observations, deliveryID: UUID(), phoneWorkoutSessionID: session,
                                     watchRequestID: request, sequence: 1, observations: [obs])
        #expect(receiver.handle(message.payload) == .persistenceFailed)
        #expect(transport.immediate.isEmpty && transport.durable.isEmpty)
        store.failSaves = false
        #expect(receiver.handle(message.payload) == .accepted(count: 1))
        #expect(!transport.durable.isEmpty)
        #expect(persisted == 2)
    }

    @Test func retiredJournalsAreNeverDroppedAtCapacity() {
        let store = FakeHRStore(), transport = FakeHRTransport()
        transport.isReachable = false
        let outbox = WatchHeartRateOutbox(store: store, transport: transport, clock: { 1_800_000_100 })
        var ids: [UUID] = []
        for i in 0...WatchHeartRateOutbox.maximumRetiredJournals {
            let id = UUID(); ids.append(id)
            #expect(outbox.bind(phoneWorkoutSessionID: id, watchRequestID: UUID()))
            outbox.record(bpm: 100, sampleEnd: Date(timeIntervalSince1970: 1_800_000_000 + Double(i)), source: .watchHealthKit)
        }
        #expect(!outbox.bind(phoneWorkoutSessionID: UUID(), watchRequestID: UUID()))
        #expect(outbox.failedRecoverably && outbox.bindingRefused)
        #expect(outbox.state?.retired.count == WatchHeartRateOutbox.maximumRetiredJournals)
        #expect(outbox.state?.retired.allSatisfy { !$0.batches.isEmpty } == true)
        #expect(outbox.record(bpm: 100, sampleEnd: Date(timeIntervalSince1970: 1_800_000_999), source: .watchHealthKit) == .notPersisted)
    }
}
