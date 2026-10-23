import Testing
import Foundation
@testable import CadenceFeatures

/// Hermetic production-flow harness (issue #306). Every scenario drives the real
/// production types (`WatchHRPreflightLedger`, `WatchHeartRateOutbox`,
/// `WatchHeartRateReceiver`, presenters) through injected store/transport/clock
/// boundaries: no network, signing, HealthKit hardware, or real sleeps.
/// Run with `scripts/run-verification-harness.sh`. A failure message starts with
/// `[harness:<scenario>]` and names the trace artifact written to
/// `$HARNESS_ARTIFACT_DIR` (default: temp dir).
@MainActor
struct ProductionFlowHarnessTests {
    let session = UUID(), request = UUID()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func tag(_ scenario: String, _ trace: [String] = []) -> Comment {
        let dir = ProcessInfo.processInfo.environment["HARNESS_ARTIFACT_DIR"]
            ?? NSTemporaryDirectory() + "cladiron-harness"
        let path = dir + "/\(scenario).trace.txt"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? trace.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        return "[harness:\(scenario)] artifact: \(path)"
    }

    private func makeOutbox(_ store: FakeHRStore = FakeHRStore(),
                            _ transport: FakeHRTransport = FakeHRTransport()) -> WatchHeartRateOutbox {
        transport.store = store
        let outbox = WatchHeartRateOutbox(store: store, transport: transport, clock: { 1_800_000_100 })
        outbox.bind(phoneWorkoutSessionID: session, watchRequestID: request, captureEpoch: testEpoch)
        return outbox
    }

    private func makePhone(known: [UUID: UUID]) -> (WatchHeartRateReceiver, Box<[UUID: [WatchHRObservation]]>) {
        let box = Box<[UUID: [WatchHRObservation]]>([:])
        let receiver = WatchHeartRateReceiver(
            store: FakeReceiptStore(), transport: FakeHRTransport(),
            expectedRoute: { known[$0].map { WatchHRRoute(requestID: $0, captureEpoch: testEpoch) } },
            persist: { id, obs in box.value[id, default: []] += obs; return true })
        return (receiver, box)
    }

    @Test func phoneHRPreflightStartFinishRecreate() {
        let c = tag("phone-hr-preflight-start-finish-recreate")
        var ledger = WatchHRPreflightLedger()
        let reservation = ledger.reserve(now: t0)
        let obs = WatchHRObservation(observationID: UUID(), source: .watchHealthKit,
                                     sampleEnd: t0.addingTimeInterval(2).timeIntervalSince1970, bpm: 90)
        #expect(ledger.buffer(obs, sessionID: reservation.phoneWorkoutSessionID) == .buffered, c)
        #expect(ledger.buffer(obs, sessionID: reservation.phoneWorkoutSessionID) == .duplicate, c)
        #expect(ledger.buffer(obs, sessionID: UUID()) == .unknown, c)
        // Recreate (process restart) from the persisted ledger.
        let data = try! JSONEncoder().encode(ledger)
        var revived = try! JSONDecoder().decode(WatchHRPreflightLedger.self, from: data)
        #expect(revived.adopt(sessionID: UUID(), start: t0, end: t0.addingTimeInterval(60)) == nil, c)
        let adopted = revived.adopt(sessionID: reservation.phoneWorkoutSessionID,
                                    start: t0, end: t0.addingTimeInterval(60))
        #expect(adopted?.count == 1, c)
        #expect(revived.buffer(obs, sessionID: reservation.phoneWorkoutSessionID) == .tombstoned, c)
    }

    @Test func transportDuplicateDropReorder() {
        let c = tag("transport-duplicate-drop-reorder")
        let transport = FakeHRTransport()
        let outbox = makeOutbox(FakeHRStore(), transport)
        for i in 0..<3 {
            outbox.record(bpm: 120 + Double(i), sampleEnd: t0.addingTimeInterval(Double(i) * 5), source: .watchHealthKit)
            outbox.flush()
        }
        let (phone, box) = makePhone(known: [session: request])
        let sent = transport.immediate.map(\.payload)
        #expect(sent.count == 3, c)
        // Reorder (3,1), duplicate (1), drop (2): exactly two persist, once each.
        #expect(phone.handle(sent[2]) == .accepted(count: 1), c)
        #expect(phone.handle(sent[0]) == .accepted(count: 1), c)
        #expect(phone.handle(sent[0]) == .duplicate, c)
        #expect(box.value[session]?.count == 2, c)
        // The dropped batch is retried and then accepted, never lost.
        #expect(phone.handle(sent[1]) == .accepted(count: 1), c)
        #expect(box.value[session]?.count == 3, c)
    }

    @Test func unboundSessionIsRejected() {
        let c = tag("production-binding-session-scope")
        let transport = FakeHRTransport()
        let outbox = makeOutbox(FakeHRStore(), transport)
        outbox.record(bpm: 120, sampleEnd: t0, source: .watchHealthKit)
        outbox.flush()
        let (phone, box) = makePhone(known: [UUID(): UUID()])
        #expect(phone.handle(transport.immediate[0].payload) == .rejected(.identityMismatch), c)
        #expect(box.value.isEmpty, c)
    }

    @Test func thisWeekSummaryAndSummaryAccessibility() {
        let c = tag("this-week-summary-accessibility")
        #expect(ThisWeekWorkoutsPresenter.summary(planned: 0, done: 0) == "No workouts planned or done", c)
        #expect(ThisWeekWorkoutsPresenter.summary(planned: 3, done: 2) == "3 workouts planned, 2 workouts done", c)
        #expect(!WorkoutSummaryPresenter.hrChartAXSummary([100, 120, 140]).isEmpty, c)
    }
}

final class Box<T> { var value: T; init(_ v: T) { value = v } }
