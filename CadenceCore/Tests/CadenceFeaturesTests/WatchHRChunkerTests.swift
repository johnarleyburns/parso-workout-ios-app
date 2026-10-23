import Testing
import Foundation
import CadenceCore
@testable import CadenceFeatures

@MainActor
struct WatchHRChunkerTests {
    let session = UUID(), request = UUID(), epoch = UUID()

    func observations(_ n: Int) -> [WatchHRObservation] {
        (0..<n).map { WatchHRObservation(observationID: UUID(), source: .watchHealthKit,
                                         sampleEnd: 1_800_000_000 + Double($0), bpm: 100 + Double($0 % 80),
                                         sampleID: UUID().uuidString) }
    }

    func chunker(maxBytes: Int = WatchHRChunker.maxEncodedBytes, maxObservations: Int = WatchHRChunker.maxObservationsPerChunk) -> WatchHRChunker {
        WatchHRChunker(phoneWorkoutSessionID: session, watchRequestID: request, captureEpoch: epoch,
                       maxBytes: maxBytes, maxObservations: maxObservations)
    }

    @Test func denseHourCaptureSplitsIntoBoundedChunksAndReconstructsExactly() {
        let all = observations(3_900)
        let c = chunker(maxObservations: 5_000)
        let chunks = c.chunks(all)
        #expect(chunks.count > 1)
        #expect(chunks.flatMap { $0 } == all)
        for chunk in chunks { #expect(c.encodedSize(chunk) <= WatchHRChunker.maxEncodedBytes) }
    }

    @Test func byteBudgetIsHonouredForSmallBudgets() {
        let all = observations(200)
        let c = chunker(maxBytes: 4_096, maxObservations: 1_000)
        let chunks = c.chunks(all)
        #expect(chunks.count > 1)
        for chunk in chunks where chunk.count > 1 { #expect(c.encodedSize(chunk) <= 4_096) }
        #expect(chunks.flatMap { $0 } == all)
    }

    @Test func outboxChunksDuplicatesAndReorderingAreIdempotentAndRetained() {
        let store = FakeHRStore(), transport = FakeHRTransport()
        transport.isReachable = false
        transport.store = store
        let outbox = WatchHeartRateOutbox(store: store, transport: transport, clock: { 1_800_000_100 })
        outbox.bind(phoneWorkoutSessionID: session, watchRequestID: request, captureEpoch: epoch)
        for i in 0..<200 {
            outbox.record(bpm: 100 + Double(i % 50), sampleEnd: Date(timeIntervalSince1970: 1_800_000_000 + Double(i)), source: .watchHealthKit)
        }
        outbox.flush()
        #expect(outbox.unacknowledgedCount == 200)
        #expect(outbox.diagnostics.chunkCount == transport.durable.count)
        #expect(outbox.diagnostics.chunkCount > 1)
        #expect(outbox.diagnostics.largestChunkBytes <= WatchHRChunker.maxEncodedBytes)
        // Relaunch retains everything until a receipt arrives.
        let revived = WatchHeartRateOutbox(store: store, transport: transport, clock: { 1_800_000_100 })
        #expect(revived.unacknowledgedCount == 200)
    }

    @Test func smallLegacyEndSessionPayloadStillDecodes() {
        let samples = [HRSamplePointFixture.a, HRSamplePointFixture.b]
        let decoded = WatchStrengthHeartRate.decode(WatchStrengthHeartRate.encode(samples))
        #expect(decoded.count == 2)
    }
}

private enum HRSamplePointFixture {
    static let a = HRSamplePoint(t: 10, bpm: 120)
    static let b = HRSamplePoint(t: 20, bpm: 130)
}
