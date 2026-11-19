#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore

/// Issue #350: Watch-started strength completion HR travels as chunked,
/// receipt-backed delivery; `end_session` carries only the route and watermark.
@MainActor
final class WatchStrengthCompletionTests {
    private var container: ModelContainer!
    private var context: ModelContext!

    init() throws {
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

    @Test func sixtyMinuteCaptureIsChunkedUnderBudgetAndReconstructsOnPhone() throws {
        let samples = dense(3600)
        let m = makeModel(samples: samples)
        let (outbox, _, transport) = makeOutbox()
        let payload = try #require(m.endSessionPayload(completionOutbox: outbox))
        outbox.flush()

        #expect(payload[WatchStrengthHeartRate.transportKey] == nil)
        let route = try #require(m.completionRoute)
        #expect(payload["hr_transfer_id"] as? String == route.transferID.uuidString)
        let final = try #require(payload["hr_final_sequence"] as? Int)
        #expect(final == transport.durable.count)
        #expect(final > 1)
        let chunker = WatchHRChunker(phoneWorkoutSessionID: route.sessionID, watchRequestID: route.transferID, captureEpoch: route.captureEpoch)
        for message in transport.durable { #expect(chunker.encodedSize(message.observations) < 48 * 1024) }

        var persisted: [WatchHRObservation] = []
        let phone = WatchHeartRateReceiver(store: FakeReceiptStore(), transport: FakeHRTransport(),
            expectedRoute: { _ in WatchHRRoute(requestID: route.transferID, captureEpoch: route.captureEpoch) },
            persist: { _, obs in persisted += obs; return true })
        try phone.registerCompletionTransfer(sessionID: route.sessionID, transferID: route.transferID,
                                             captureEpoch: route.captureEpoch, finalSequence: final) { _ in }
        #expect(!phone.isFinalizationComplete(sessionID: route.sessionID))
        for message in transport.durable { phone.handle(message.payload) }
        // A resend is acknowledged but never stored twice.
        for message in transport.durable { #expect(phone.handle(message.payload) == .duplicate) }
        #expect(phone.isFinalizationComplete(sessionID: route.sessionID))
        let start = try #require(m.session).date.timeIntervalSince1970
        #expect(persisted.sorted { $0.sampleEnd < $1.sampleEnd }.map { HRSamplePoint(t: $0.sampleEnd - start, bpm: $0.bpm) } == samples)
    }

    @Test func endSessionStaysSmall() throws {
        let m = makeModel(samples: dense(3600 * 3))
        let (outbox, _, _) = makeOutbox()
        let payload = try #require(m.endSessionPayload(completionOutbox: outbox))
        let size = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0).count
        #expect(size < 4 * 1024)
    }

    @Test func unreachableRelaunchAndLateReceiptRetainChunks() throws {
        let m = makeModel(samples: dense(300))
        let store = FakeHRStore(), transport = FakeHRTransport()
        transport.isReachable = false
        let (outbox, _, _) = makeOutbox(store: store, transport: transport)
        _ = try #require(m.endSessionPayload(completionOutbox: outbox))
        outbox.flush()
        let count = transport.durable.count
        #expect(count > 0)
        #expect(outbox.outbox.unacknowledgedCount == 300)

        // Watch relaunch: a new outbox restores the persisted journal and retries.
        let relaunchTransport = FakeHRTransport()
        relaunchTransport.store = store
        let relaunched = WatchStrengthCompletionOutbox(outbox: WatchHeartRateOutbox(
            store: store, transport: relaunchTransport, clock: { 1_800_000_500 }))
        #expect(relaunched.outbox.unacknowledgedCount == 300)
        relaunched.retry(reason: "test")
        #expect(relaunchTransport.durable.count == count)

        // Late receipt: only now do chunks leave the journal.
        let route = try #require(m.completionRoute)
        let phoneTransport = FakeHRTransport()
        let phone = WatchHeartRateReceiver(store: FakeReceiptStore(), transport: phoneTransport,
            expectedRoute: { _ in WatchHRRoute(requestID: route.transferID, captureEpoch: route.captureEpoch) },
            persist: { _, _ in true })
        for message in relaunchTransport.durable { phone.handle(message.payload) }
        #expect(relaunched.hasUnacknowledgedChunks)
        for ack in phoneTransport.durable { relaunched.handleAcknowledgement(ack) }
        #expect(!relaunched.hasUnacknowledgedChunks)
    }

    @Test func oversizedChunkIsRetainedAndFlagged() throws {
        let m = makeModel(samples: dense(10))
        let (outbox, _, transport) = makeOutbox()
        let tiny = WatchHeartRateOutbox.maximumBatchSize
        #expect(tiny > 0)
        // Force the journal to hold a chunk beyond the budget.
        let route = WatchStrengthCompletionRoute(sessionID: UUID(), transferID: UUID(), captureEpoch: UUID())
        #expect(outbox.enqueue(samples: dense(5), startedAt: Date(timeIntervalSince1970: 1_800_000_000), route: route) != nil)
        var state = try #require(outbox.outbox.state)
        let big = WatchHRObservation(observationID: UUID(), source: .watchHealthKit, sampleEnd: 1_800_000_001, bpm: 100,
                                     sampleID: String(repeating: "x", count: 60 * 1024))
        state.batches[0].observations = [big]
        let store = FakeHRStore(); store.saved = state
        let reloaded = WatchStrengthCompletionOutbox(outbox: WatchHeartRateOutbox(store: store, transport: transport, clock: { 1_800_000_100 }))
        reloaded.flush()
        #expect(reloaded.failedRecoverably)
        #expect(reloaded.hasUnacknowledgedChunks)
        _ = m
    }

    @Test func legacySmallPayloadStillDecodes() {
        let samples = dense(5)
        #expect(WatchStrengthHeartRate.decode(WatchStrengthHeartRate.encode(samples)) == samples)
    }
}

/// Issue #627: completion sealing honors the aggregate retention bound.
@MainActor
struct WatchCompletionBoundTests {
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

    @Test func sealCompletionNeverExceedsMaximumRetainedObservations() {
        let (outbox, _, _) = seeded(pending: max - 10, sealed: 0)
        let before = outbox.state!.pending
        let points = (0..<100).map { (bpm: 120.0, sampleEnd: 2_000_000.0 + Double($0)) }
        #expect(outbox.sealCompletion(points) != nil)
        #expect(outbox.unacknowledgedCount <= max)
        let kept = Set(outbox.state!.batches.flatMap(\.observations).map(\.observationID))
        #expect(before.allSatisfy { kept.contains($0.observationID) })
    }

    @Test func sealCompletionUsesDeterministicCompactionBeforeRejectingNewPoints() {
        let (outbox, _, _) = seeded(pending: max - 2, sealed: 0)
        let points = [(100.0, 10.0 + 2_000_000), (150.0, 11.0 + 2_000_000), (140.0, 12.0 + 2_000_000), (110.0, 13.0 + 2_000_000)]
            .map { (bpm: $0.0, sampleEnd: $0.1) }
        #expect(outbox.sealCompletion(points.reversed()) != nil)
        let tail = outbox.state!.batches.flatMap(\.observations).filter { $0.sampleEnd >= 2_000_000 }
        #expect(tail.map(\.bpm) == [150, 140])
        #expect(tail.map(\.sampleEnd) == [2_000_011, 2_000_012])
    }

    @Test func sealCompletionReportsFailureWithoutDeliveryWhenBoundCannotBeMet() {
        let (outbox, store, transport) = seeded(pending: 0, sealed: max)
        let before = outbox.state!
        #expect(outbox.sealCompletion([(bpm: 120, sampleEnd: 2_000_000)]) == nil)
        #expect(outbox.failedRecoverably)
        #expect(outbox.state == before)
        #expect(store.saved == before)
        #expect(transport.durable.isEmpty && transport.immediate.isEmpty)
    }

    @Test func completionSeenKeysRemainBoundedWithRetainedObservations() {
        let (outbox, _, _) = seeded(pending: 0, sealed: 0)
        let points = (0..<(max + 500)).map { (bpm: 90.0 + Double($0 % 50), sampleEnd: 1_000.0 + Double($0)) }
        #expect(outbox.sealCompletion(points) != nil)
        #expect(outbox.unacknowledgedCount <= max)
        #expect(outbox.state!.seenKeys.count <= outbox.unacknowledgedCount)
    }
}
#endif
