import XCTest
import SwiftData
@testable import CadenceFeatures
import CadenceCore

/// Issue #350: Watch-started strength completion HR travels as chunked,
/// receipt-backed delivery; `end_session` carries only the route and watermark.
@MainActor
final class WatchStrengthCompletionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try CadenceStore.makeModelContainer(inMemory: true)
        context = ModelContext(container)
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
    }

    private func dense(_ seconds: Int) -> [HRSamplePoint] {
        (0..<seconds).map { HRSamplePoint(t: Double($0), bpm: 100 + Double($0 % 60)) }
    }

    private func makeOutbox(store: FakeHRStore = FakeHRStore(), transport: FakeHRTransport = FakeHRTransport())
        -> (WatchStrengthCompletionOutbox, FakeHRStore, FakeHRTransport) {
        transport.store = store
        let outbox = WatchHeartRateOutbox(store: store, transport: transport, clock: { 1_800_000_100 })
        return (WatchStrengthCompletionOutbox(outbox: outbox), store, transport)
    }

    private func makeModel(samples: [HRSamplePoint]) -> WatchStrengthFlowModel {
        let m = WatchStrengthFlowModel(context: context, unit: .kilograms, cooldownDefault: 5, restDefault: 90)
        m.start(title: "Push", plannedExerciseNames: ["Bench Press"], createSession: true)
        m.recordHeartRate(samples)
        return m
    }

    func testSixtyMinuteCaptureIsChunkedUnderBudgetAndReconstructsOnPhone() throws {
        let samples = dense(3600)
        let m = makeModel(samples: samples)
        let (outbox, _, transport) = makeOutbox()
        let payload = try XCTUnwrap(m.endSessionPayload(completionOutbox: outbox))
        outbox.flush()

        XCTAssertNil(payload[WatchStrengthHeartRate.transportKey])
        let route = try XCTUnwrap(m.completionRoute)
        XCTAssertEqual(payload["hr_transfer_id"] as? String, route.transferID.uuidString)
        let final = try XCTUnwrap(payload["hr_final_sequence"] as? Int)
        XCTAssertEqual(final, transport.durable.count)
        XCTAssertGreaterThan(final, 1)
        let chunker = WatchHRChunker(phoneWorkoutSessionID: route.sessionID, watchRequestID: route.transferID, captureEpoch: route.captureEpoch)
        for message in transport.durable { XCTAssertLessThan(chunker.encodedSize(message.observations), 48 * 1024) }

        var persisted: [WatchHRObservation] = []
        let phone = WatchHeartRateReceiver(store: FakeReceiptStore(), transport: FakeHRTransport(),
            expectedRoute: { _ in WatchHRRoute(requestID: route.transferID, captureEpoch: route.captureEpoch) },
            persist: { _, obs in persisted += obs; return true })
        try phone.registerCompletionTransfer(sessionID: route.sessionID, transferID: route.transferID,
                                             captureEpoch: route.captureEpoch, finalSequence: final) { _ in }
        XCTAssertFalse(phone.isFinalizationComplete(sessionID: route.sessionID))
        for message in transport.durable { phone.handle(message.payload) }
        // A resend is acknowledged but never stored twice.
        for message in transport.durable { XCTAssertEqual(phone.handle(message.payload), .duplicate) }
        XCTAssertTrue(phone.isFinalizationComplete(sessionID: route.sessionID))
        let start = try XCTUnwrap(m.session).date.timeIntervalSince1970
        XCTAssertEqual(persisted.sorted { $0.sampleEnd < $1.sampleEnd }.map { HRSamplePoint(t: $0.sampleEnd - start, bpm: $0.bpm) }, samples)
    }

    func testEndSessionStaysSmall() throws {
        let m = makeModel(samples: dense(3600 * 3))
        let (outbox, _, _) = makeOutbox()
        let payload = try XCTUnwrap(m.endSessionPayload(completionOutbox: outbox))
        let size = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0).count
        XCTAssertLessThan(size, 4 * 1024)
    }

    func testUnreachableRelaunchAndLateReceiptRetainChunks() throws {
        let m = makeModel(samples: dense(300))
        let store = FakeHRStore(), transport = FakeHRTransport()
        transport.isReachable = false
        let (outbox, _, _) = makeOutbox(store: store, transport: transport)
        _ = try XCTUnwrap(m.endSessionPayload(completionOutbox: outbox))
        outbox.flush()
        let count = transport.durable.count
        XCTAssertGreaterThan(count, 0)
        XCTAssertEqual(outbox.outbox.unacknowledgedCount, 300)

        // Watch relaunch: a new outbox restores the persisted journal and retries.
        let relaunchTransport = FakeHRTransport()
        relaunchTransport.store = store
        let relaunched = WatchStrengthCompletionOutbox(outbox: WatchHeartRateOutbox(
            store: store, transport: relaunchTransport, clock: { 1_800_000_500 }))
        XCTAssertEqual(relaunched.outbox.unacknowledgedCount, 300)
        relaunched.retry(reason: "test")
        XCTAssertEqual(relaunchTransport.durable.count, count)

        // Late receipt: only now do chunks leave the journal.
        let route = try XCTUnwrap(m.completionRoute)
        let phoneTransport = FakeHRTransport()
        let phone = WatchHeartRateReceiver(store: FakeReceiptStore(), transport: phoneTransport,
            expectedRoute: { _ in WatchHRRoute(requestID: route.transferID, captureEpoch: route.captureEpoch) },
            persist: { _, _ in true })
        for message in relaunchTransport.durable { phone.handle(message.payload) }
        XCTAssertTrue(relaunched.hasUnacknowledgedChunks)
        for ack in phoneTransport.durable { relaunched.handleAcknowledgement(ack) }
        XCTAssertFalse(relaunched.hasUnacknowledgedChunks)
    }

    func testOversizedChunkIsRetainedAndFlagged() throws {
        let m = makeModel(samples: dense(10))
        let (outbox, _, transport) = makeOutbox()
        let tiny = WatchHeartRateOutbox.maximumBatchSize
        XCTAssertGreaterThan(tiny, 0)
        // Force the journal to hold a chunk beyond the budget.
        let route = WatchStrengthCompletionRoute(sessionID: UUID(), transferID: UUID(), captureEpoch: UUID())
        XCTAssertNotNil(outbox.enqueue(samples: dense(5), startedAt: Date(timeIntervalSince1970: 1_800_000_000), route: route))
        var state = try XCTUnwrap(outbox.outbox.state)
        let big = WatchHRObservation(observationID: UUID(), source: .watchHealthKit, sampleEnd: 1_800_000_001, bpm: 100,
                                     sampleID: String(repeating: "x", count: 60 * 1024))
        state.batches[0].observations = [big]
        let store = FakeHRStore(); store.saved = state
        let reloaded = WatchStrengthCompletionOutbox(outbox: WatchHeartRateOutbox(store: store, transport: transport, clock: { 1_800_000_100 }))
        reloaded.flush()
        XCTAssertTrue(reloaded.failedRecoverably)
        XCTAssertTrue(reloaded.hasUnacknowledgedChunks)
        _ = m
    }

    func testLegacySmallPayloadStillDecodes() {
        let samples = dense(5)
        XCTAssertEqual(WatchStrengthHeartRate.decode(WatchStrengthHeartRate.encode(samples)), samples)
    }
}

/// Issue #627: completion sealing honors the aggregate retention bound.
@MainActor
final class WatchCompletionBoundTests: XCTestCase {
    private let max = WatchHeartRateOutbox.maximumRetainedObservations

    private func obs(_ t: Double, _ bpm: Double) -> WatchHRObservation {
        WatchHRObservation(observationID: UUID(), source: .watchHealthKit, sampleEnd: t, bpm: bpm)
    }

    private func seeded(pending: Int, sealed: Int) -> (WatchHeartRateOutbox, FakeHRStore, FakeHRTransport) {
        var s = WatchHeartRateOutboxState(phoneWorkoutSessionID: UUID(), watchRequestID: UUID(), captureEpoch: UUID())
        s.pending = (0..<pending).map { obs(Double($0 + 1), 100) }
        if sealed > 0 {
            s.batches = [.init(deliveryID: UUID(), sequence: 1,
                               observations: (0..<sealed).map { obs(Double(1_000_000 + $0), 100) }, durableQueuedAt: nil)]
            s.nextSequence = 2
        }
        let store = FakeHRStore(); store.saved = s
        let transport = FakeHRTransport()
        return (WatchHeartRateOutbox(store: store, transport: transport, clock: { 1_800_000_100 }), store, transport)
    }

    func testSealCompletionNeverExceedsMaximumRetainedObservations() {
        let (outbox, _, _) = seeded(pending: max - 10, sealed: 0)
        let before = outbox.state!.pending
        let points = (0..<100).map { (bpm: 120.0, sampleEnd: 2_000_000.0 + Double($0)) }
        XCTAssertNotNil(outbox.sealCompletion(points))
        XCTAssertLessThanOrEqual(outbox.unacknowledgedCount, max)
        let kept = Set(outbox.state!.batches.flatMap(\.observations).map(\.observationID))
        XCTAssertTrue(before.allSatisfy { kept.contains($0.observationID) })
    }

    func testSealCompletionUsesDeterministicCompactionBeforeRejectingNewPoints() {
        let (outbox, _, _) = seeded(pending: max - 2, sealed: 0)
        let points = [(100.0, 10.0 + 2_000_000), (150.0, 11.0 + 2_000_000), (140.0, 12.0 + 2_000_000), (110.0, 13.0 + 2_000_000)]
            .map { (bpm: $0.0, sampleEnd: $0.1) }
        XCTAssertNotNil(outbox.sealCompletion(points.reversed()))
        let tail = outbox.state!.batches.flatMap(\.observations).filter { $0.sampleEnd >= 2_000_000 }
        XCTAssertEqual(tail.map(\.bpm), [150, 140])
        XCTAssertEqual(tail.map(\.sampleEnd), [2_000_011, 2_000_012])
    }

    func testSealCompletionReportsFailureWithoutDeliveryWhenBoundCannotBeMet() {
        let (outbox, store, transport) = seeded(pending: 0, sealed: max)
        let before = outbox.state!
        XCTAssertNil(outbox.sealCompletion([(bpm: 120, sampleEnd: 2_000_000)]))
        XCTAssertTrue(outbox.failedRecoverably)
        XCTAssertEqual(outbox.state, before)
        XCTAssertEqual(store.saved, before)
        XCTAssertTrue(transport.durable.isEmpty && transport.immediate.isEmpty)
    }

    func testCompletionSeenKeysRemainBoundedWithRetainedObservations() {
        let (outbox, _, _) = seeded(pending: 0, sealed: 0)
        let points = (0..<(max + 500)).map { (bpm: 90.0 + Double($0 % 50), sampleEnd: 1_000.0 + Double($0)) }
        XCTAssertNotNil(outbox.sealCompletion(points))
        XCTAssertLessThanOrEqual(outbox.unacknowledgedCount, max)
        XCTAssertLessThanOrEqual(outbox.state!.seenKeys.count, outbox.unacknowledgedCount)
    }
}
