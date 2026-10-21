import XCTest
@testable import CadenceFeatures

private final class MemoryLedgerStore: WatchSyncLedgerStore {
    var ledger: WatchSyncLedger?
    func load() -> WatchSyncLedger? { ledger }
    func save(_ ledger: WatchSyncLedger) { self.ledger = ledger }
}

private final class Clock { var now = Date(timeIntervalSince1970: 1_000_000) }

final class WatchSyncHandshakeTests: XCTestCase {
    private let a = WatchSyncHandshake.Components(preferences: "p1", customExercises: "c1", todayPlan: "t1", weekSummary: "w1")
    private var b: WatchSyncHandshake.Components { var c = a; c.preferences = "p2"; return c }

    private func make(_ store: MemoryLedgerStore = MemoryLedgerStore(), _ clock: Clock = Clock(),
                      legacy: Date? = nil) -> WatchSyncTracker {
        WatchSyncTracker(store: store, clock: { clock.now }, legacyLastSyncAt: legacy)
    }

    private func ack(_ e: WatchSyncHandshake.Envelope) -> WatchSyncHandshake.Ack {
        .init(revision: e.revision, snapshotID: e.snapshotID, components: e.components)
    }

    func testLocalWriteWithoutAckIsAwaitingNotUpToDate() {
        let t = make()
        let e = t.prepare(components: a, trigger: .contentChanged)!
        XCTAssertEqual(t.state(installed: true, activated: true), .queued(revision: 1, since: Date(timeIntervalSince1970: 1_000_000)))
        t.markWritten(revision: e.revision)
        guard case .awaitingWatch = t.state(installed: true, activated: true) else { return XCTFail() }
        XCTAssertNil(t.lastConfirmedAt)
    }

    func testMatchingAckConfirmsAndPersistsAcrossRecreation() {
        let store = MemoryLedgerStore(), clock = Clock()
        let t = make(store, clock)
        let e = t.prepare(components: a, trigger: .contentChanged)!
        clock.now += 5
        XCTAssertEqual(t.receive(ack: ack(e)), .confirmed)
        let t2 = make(store, clock)
        XCTAssertEqual(t2.state(installed: true, activated: true), .upToDate(confirmedAt: clock.now))
        XCTAssertEqual(t2.ledger.lastConfirmedRevision, 1)
    }

    func testDuplicateAndWrongAcksCannotConfirm() {
        let t = make()
        let e1 = t.prepare(components: a, trigger: .contentChanged)!
        XCTAssertEqual(t.receive(ack: ack(e1)), .confirmed)
        XCTAssertEqual(t.receive(ack: ack(e1)), .duplicate)
        let e2 = t.prepare(components: b, trigger: .contentChanged)!
        XCTAssertEqual(t.receive(ack: ack(e1)), .duplicate)
        var wrongID = ack(e2); wrongID.snapshotID = UUID()
        XCTAssertEqual(t.receive(ack: wrongID), .ignored)
        var wrongVersion = ack(e2); wrongVersion.protocolVersion = 99
        XCTAssertEqual(t.receive(ack: wrongVersion), .incompatible)
        XCTAssertEqual(t.state(installed: true, activated: true),
                       .failedRecoverably(reason: .incompatibleVersion, lastConfirmedAt: t.lastConfirmedAt))
        XCTAssertEqual(t.ledger.pending?.revision, 2)
    }

    func testDurableAckArrivingLaterConfirmsOnce() {
        let t = make()
        let e = t.prepare(components: a, trigger: .contentChanged)!
        let receiverDecision = WatchSyncReceiveDecision.decide(context: e.contextEntries, applied: nil)
        XCTAssertEqual(receiverDecision, .apply)
        let record = WatchSyncAppliedRecord(revision: e.revision, snapshotID: e.snapshotID, components: e.components)
        XCTAssertEqual(WatchSyncReceiveDecision.decide(context: e.contextEntries, applied: record), .duplicate)
        let roundTrip = WatchSyncHandshake.Ack(message: record.ack.message)!
        XCTAssertEqual(t.receive(ack: roundTrip), .confirmed)
        XCTAssertEqual(t.receive(ack: roundTrip), .duplicate)
    }

    func testTimeoutBecomesStaleThenRetryGetsNewRevisionAndConfirms() {
        let clock = Clock(); let t = make(MemoryLedgerStore(), clock)
        let e1 = t.prepare(components: a, trigger: .contentChanged)!
        t.markWritten(revision: 1)
        clock.now += WatchSyncHandshake.ackTimeout + 1
        XCTAssertEqual(t.state(installed: true, activated: true), .stale(lastConfirmedAt: nil))
        XCTAssertTrue(t.mayReconcile(.periodic))
        let e2 = t.prepare(components: a, trigger: .periodic)!
        XCTAssertEqual(e2.revision, 2)
        XCTAssertNotEqual(e1.snapshotID, e2.snapshotID)
        XCTAssertEqual(t.receive(ack: ack(e1)), .ignored)
        XCTAssertEqual(t.receive(ack: ack(e2)), .confirmed)
    }

    func testBackoffGrowsAndIsCapped() {
        let clock = Clock(); let t = make(MemoryLedgerStore(), clock)
        _ = t.prepare(components: a, trigger: .contentChanged)
        clock.now += 121
        _ = t.prepare(components: a, trigger: .periodic)      // attempt 2: next delay 240
        clock.now += 121
        XCTAssertFalse(t.mayReconcile(.periodic))
        clock.now += 120
        XCTAssertTrue(t.mayReconcile(.periodic))
        for _ in 0..<10 { clock.now += 2000; _ = t.prepare(components: a, trigger: .periodic) }
        clock.now += WatchSyncHandshake.maximumBackoff - 1
        XCTAssertFalse(t.mayReconcile(.periodic))
    }

    func testChangesDuringUnackedWriteCoalesceToLatest() {
        let t = make()
        let e1 = t.prepare(components: a, trigger: .contentChanged)!
        let e2 = t.prepare(components: b, trigger: .contentChanged)!
        XCTAssertEqual(t.ledger.pending, e2)
        XCTAssertEqual(t.receive(ack: ack(e1)), .ignored)
        XCTAssertNil(t.lastConfirmedAt)
        XCTAssertEqual(t.receive(ack: ack(e2)), .confirmed)
        XCTAssertNil(t.prepare(components: b, trigger: .contentChanged))
    }

    func testLifecycleTriggersReconcileWithUnchangedFingerprintOnlyWhenNeeded() {
        let clock = Clock(); let t = make(MemoryLedgerStore(), clock)
        let e = t.prepare(components: a, trigger: .contentChanged)!
        // Unacknowledged: activation right away is bounded, later is allowed.
        XCTAssertNil(t.prepare(components: a, trigger: .activation))
        clock.now += 31
        XCTAssertNotNil(t.prepare(components: a, trigger: .reachability))
        let e2 = t.ledger.pending!
        _ = e
        t.receive(ack: ack(e2))
        // Fresh confirmation: no write; stale confirmation: reconcile.
        clock.now += 10
        XCTAssertNil(t.prepare(components: a, trigger: .activation))
        clock.now += WatchSyncHandshake.reconcileInterval
        XCTAssertNotNil(t.prepare(components: a, trigger: .activation))
    }

    func testRapidEventsAreBounded() {
        let t = make()
        var writes = 0
        for _ in 0..<50 {
            if t.prepare(components: a, trigger: .activation) != nil { writes += 1 }
            if t.prepare(components: a, trigger: .contentChanged) != nil { writes += 1 }
        }
        XCTAssertEqual(writes, 1)
    }

    func testWatchBehindOrAheadOrIncompatibleStatus() {
        let t = make()
        let e = t.prepare(components: a, trigger: .contentChanged)!
        t.receive(ack: ack(e))
        let e2 = t.prepare(components: b, trigger: .contentChanged)!
        t.receive(ack: ack(e2))
        XCTAssertEqual(t.receive(ack: .init(revision: 1, snapshotID: nil, components: nil)), .watchBehind)
        XCTAssertTrue(t.mayReconcile(.watchRequest))
        XCTAssertEqual(t.receive(ack: .init(revision: 40, snapshotID: UUID(), components: nil)), .watchAhead)
        XCTAssertEqual(t.prepare(components: b, trigger: .watchRequest)!.revision, 41)
        XCTAssertEqual(t.receiveWatchRequest(appliedRevision: 1, protocolVersion: 7), .incompatible)
        let state = t.state(installed: true, activated: true)
        XCTAssertEqual(state, .failedRecoverably(reason: .incompatibleVersion, lastConfirmedAt: t.lastConfirmedAt))
        XCTAssertNotNil(t.lastConfirmedAt, "existing confirmation retained")
    }

    func testWatchRequestForcesRevisionWithoutManualAction() {
        let clock = Clock(); let t = make(MemoryLedgerStore(), clock)
        let e = t.prepare(components: a, trigger: .contentChanged)!
        t.receive(ack: ack(e))
        clock.now += 1
        XCTAssertNotNil(t.prepare(components: a, trigger: .watchRequest))
    }

    func testLegacyStateIsUnconfirmedUntilHandshake() {
        let t = make(legacy: Date(timeIntervalSince1970: 5))
        XCTAssertNil(t.lastConfirmedAt)
        XCTAssertEqual(t.state(installed: true, activated: true), .stale(lastConfirmedAt: nil))
        let legacyContext: [String: Any] = ["settings.unit": "kg"]
        XCTAssertEqual(WatchSyncReceiveDecision.decide(context: legacyContext, applied: nil), .legacy)
        let e = t.prepare(components: .init(context: legacyContext), trigger: .activation)!
        XCTAssertEqual(t.receive(ack: ack(e)), .confirmed)
    }

    func testReceiverRejectsStaleAndIncompatible() {
        let e = WatchSyncHandshake.Envelope(revision: 5, createdAt: Date(), components: a)
        let applied = WatchSyncAppliedRecord(revision: 7, snapshotID: UUID(), components: a)
        XCTAssertEqual(WatchSyncReceiveDecision.decide(context: e.contextEntries, applied: applied), .stale)
        var ctx = e.contextEntries; ctx[WatchSyncHandshake.Key.protocolVersion] = 2
        XCTAssertEqual(WatchSyncReceiveDecision.decide(context: ctx, applied: nil), .incompatible)
    }

    func testFingerprintsAreStableAndIgnoreUpdatedAt() {
        let c1: [String: Any] = ["settings.unit": "kg", "week.sets": 3, "week.updatedAt": Date(timeIntervalSince1970: 1)]
        let c2: [String: Any] = ["settings.unit": "kg", "week.sets": 3, "week.updatedAt": Date(timeIntervalSince1970: 99)]
        XCTAssertEqual(WatchSyncHandshake.Components(context: c1), WatchSyncHandshake.Components(context: c2))
        let c3: [String: Any] = ["settings.unit": "lb", "week.sets": 3]
        XCTAssertNotEqual(WatchSyncHandshake.Components(context: c1).preferences, WatchSyncHandshake.Components(context: c3).preferences)
        XCTAssertEqual(WatchSyncHandshake.Components(context: c1).weekSummary, WatchSyncHandshake.Components(context: c3).weekSummary)
    }

    func testStateTextNeverLeaksIdentifiersAndCoversStates() {
        let states: [WatchSyncState] = [.notInstalled, .activating, .upToDate(confirmedAt: Date()),
            .queued(revision: 4242, since: Date()), .awaitingWatch(revision: 4242, since: Date()), .reconciling,
            .stale(lastConfirmedAt: nil), .failedRecoverably(reason: .writeFailed, lastConfirmedAt: nil)]
        for s in states {
            XCTAssertFalse(s.summaryText.isEmpty)
            XCTAssertFalse(s.accessibilityText(lastConfirmedAt: nil).contains("4242"))
        }
        XCTAssertEqual(WatchSyncState.queued(revision: 1, since: Date()).summaryText, "Pending")
        XCTAssertEqual(WatchSyncState.awaitingWatch(revision: 1, since: Date()).summaryText, "Waiting for Apple Watch")
    }
}
