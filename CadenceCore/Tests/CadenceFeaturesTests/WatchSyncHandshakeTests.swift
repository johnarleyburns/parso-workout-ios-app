import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadencePhoneFeatures

private final class MemoryLedgerStore: WatchSyncLedgerStore {
    var ledger: WatchSyncLedger?
    func load() -> WatchSyncLedger? { ledger }
    func save(_ ledger: WatchSyncLedger) { self.ledger = ledger }
}

private final class Clock { var now = Date(timeIntervalSince1970: 1_000_000) }

struct WatchSyncHandshakeTests {
    private let a = WatchSyncHandshake.Components(preferences: "p1", customExercises: "c1", todayPlan: "t1", weekSummary: "w1")
    private var b: WatchSyncHandshake.Components { var c = a; c.preferences = "p2"; return c }

    private func make(_ store: MemoryLedgerStore = MemoryLedgerStore(), _ clock: Clock = Clock(),
                      legacy: Date? = nil) -> WatchSyncTracker {
        WatchSyncTracker(store: store, clock: { clock.now }, legacyLastSyncAt: legacy)
    }

    private func ack(_ e: WatchSyncHandshake.Envelope) -> WatchSyncHandshake.Ack {
        .init(revision: e.revision, snapshotID: e.snapshotID, components: e.components)
    }

    @Test func localWriteWithoutAckIsAwaitingNotUpToDate() {
        let t = make()
        let e = t.prepare(components: a, trigger: .contentChanged)!
        #expect(t.state(installed: true, activated: true) == .queued(revision: 1, since: Date(timeIntervalSince1970: 1_000_000)))
        t.markWritten(revision: e.revision)
        guard case .awaitingWatch = t.state(installed: true, activated: true) else {
            Issue.record()
            return
        }
        #expect(t.lastConfirmedAt == nil)
    }

    @Test func matchingAckConfirmsAndPersistsAcrossRecreation() {
        let store = MemoryLedgerStore(), clock = Clock()
        let t = make(store, clock)
        let e = t.prepare(components: a, trigger: .contentChanged)!
        clock.now += 5
        #expect(t.receive(ack: ack(e)) == .confirmed)
        let t2 = make(store, clock)
        #expect(t2.state(installed: true, activated: true) == .upToDate(confirmedAt: clock.now))
        #expect(t2.ledger.lastConfirmedRevision == 1)
    }

    @Test func duplicateAndWrongAcksCannotConfirm() {
        let t = make()
        let e1 = t.prepare(components: a, trigger: .contentChanged)!
        #expect(t.receive(ack: ack(e1)) == .confirmed)
        #expect(t.receive(ack: ack(e1)) == .duplicate)
        let e2 = t.prepare(components: b, trigger: .contentChanged)!
        #expect(t.receive(ack: ack(e1)) == .duplicate)
        var wrongID = ack(e2); wrongID.snapshotID = UUID()
        #expect(t.receive(ack: wrongID) == .ignored)
        var wrongVersion = ack(e2); wrongVersion.protocolVersion = 99
        #expect(t.receive(ack: wrongVersion) == .incompatible)
        #expect(t.state(installed: true, activated: true) ==
                       .failedRecoverably(reason: .incompatibleVersion, lastConfirmedAt: t.lastConfirmedAt))
        #expect(t.ledger.pending?.revision == 2)
    }

    @Test func durableAckArrivingLaterConfirmsOnce() {
        let t = make()
        let e = t.prepare(components: a, trigger: .contentChanged)!
        let receiverDecision = WatchSyncReceiveDecision.decide(context: e.contextEntries, applied: nil)
        #expect(receiverDecision == .apply)
        let record = WatchSyncAppliedRecord(revision: e.revision, snapshotID: e.snapshotID, components: e.components)
        #expect(WatchSyncReceiveDecision.decide(context: e.contextEntries, applied: record) == .duplicate)
        let roundTrip = WatchSyncHandshake.Ack(message: record.ack.message)!
        #expect(t.receive(ack: roundTrip) == .confirmed)
        #expect(t.receive(ack: roundTrip) == .duplicate)
    }

    @Test func timeoutBecomesStaleThenRetryGetsNewRevisionAndConfirms() {
        let clock = Clock(); let t = make(MemoryLedgerStore(), clock)
        let e1 = t.prepare(components: a, trigger: .contentChanged)!
        t.markWritten(revision: 1)
        clock.now += WatchSyncHandshake.ackTimeout + 1
        #expect(t.state(installed: true, activated: true) == .stale(lastConfirmedAt: nil))
        #expect(t.mayReconcile(.periodic))
        let e2 = t.prepare(components: a, trigger: .periodic)!
        #expect(e2.revision == 2)
        #expect(e1.snapshotID != e2.snapshotID)
        #expect(t.receive(ack: ack(e1)) == .ignored)
        #expect(t.receive(ack: ack(e2)) == .confirmed)
    }

    @Test func backoffGrowsAndIsCapped() {
        let clock = Clock(); let t = make(MemoryLedgerStore(), clock)
        _ = t.prepare(components: a, trigger: .contentChanged)
        clock.now += 121
        _ = t.prepare(components: a, trigger: .periodic)      // attempt 2: next delay 240
        clock.now += 121
        #expect(!t.mayReconcile(.periodic))
        clock.now += 120
        #expect(t.mayReconcile(.periodic))
        for _ in 0..<10 { clock.now += 2000; _ = t.prepare(components: a, trigger: .periodic) }
        clock.now += WatchSyncHandshake.maximumBackoff - 1
        #expect(!t.mayReconcile(.periodic))
    }

    @Test func changesDuringUnackedWriteCoalesceToLatest() {
        let t = make()
        let e1 = t.prepare(components: a, trigger: .contentChanged)!
        let e2 = t.prepare(components: b, trigger: .contentChanged)!
        #expect(t.ledger.pending == e2)
        #expect(t.receive(ack: ack(e1)) == .ignored)
        #expect(t.lastConfirmedAt == nil)
        #expect(t.receive(ack: ack(e2)) == .confirmed)
        #expect(t.prepare(components: b, trigger: .contentChanged) == nil)
    }

    @Test func lifecycleTriggersReconcileWithUnchangedFingerprintOnlyWhenNeeded() {
        let clock = Clock(); let t = make(MemoryLedgerStore(), clock)
        let e = t.prepare(components: a, trigger: .contentChanged)!
        // Unacknowledged: activation right away is bounded, later is allowed.
        #expect(t.prepare(components: a, trigger: .activation) == nil)
        clock.now += 31
        #expect(t.prepare(components: a, trigger: .reachability) != nil)
        let e2 = t.ledger.pending!
        _ = e
        t.receive(ack: ack(e2))
        // Fresh confirmation: no write; stale confirmation: reconcile.
        clock.now += 10
        #expect(t.prepare(components: a, trigger: .activation) == nil)
        clock.now += WatchSyncHandshake.reconcileInterval
        #expect(t.prepare(components: a, trigger: .activation) != nil)
    }

    @Test func rapidEventsAreBounded() {
        let t = make()
        var writes = 0
        for _ in 0..<50 {
            if t.prepare(components: a, trigger: .activation) != nil { writes += 1 }
            if t.prepare(components: a, trigger: .contentChanged) != nil { writes += 1 }
        }
        #expect(writes == 1)
    }

    @Test func watchBehindOrAheadOrIncompatibleStatus() {
        let t = make()
        let e = t.prepare(components: a, trigger: .contentChanged)!
        t.receive(ack: ack(e))
        let e2 = t.prepare(components: b, trigger: .contentChanged)!
        t.receive(ack: ack(e2))
        #expect(t.receive(ack: .init(revision: 1, snapshotID: nil, components: nil)) == .watchBehind)
        #expect(t.mayReconcile(.watchRequest))
        #expect(t.receive(ack: .init(revision: 40, snapshotID: UUID(), components: nil)) == .watchAhead)
        #expect(t.prepare(components: b, trigger: .watchRequest)!.revision == 41)
        #expect(t.receiveWatchRequest(appliedRevision: 1, protocolVersion: 7) == .incompatible)
        let state = t.state(installed: true, activated: true)
        #expect(state == .failedRecoverably(reason: .incompatibleVersion, lastConfirmedAt: t.lastConfirmedAt))
        #expect(t.lastConfirmedAt != nil, "existing confirmation retained")
    }

    @Test func watchRequestForcesRevisionWithoutManualAction() {
        let clock = Clock(); let t = make(MemoryLedgerStore(), clock)
        let e = t.prepare(components: a, trigger: .contentChanged)!
        t.receive(ack: ack(e))
        clock.now += 1
        #expect(t.prepare(components: a, trigger: .watchRequest) != nil)
    }

    @Test func legacyStateIsUnconfirmedUntilHandshake() {
        let t = make(legacy: Date(timeIntervalSince1970: 5))
        #expect(t.lastConfirmedAt == nil)
        #expect(t.state(installed: true, activated: true) == .stale(lastConfirmedAt: nil))
        let legacyContext: [String: Any] = ["settings.unit": "kg"]
        #expect(WatchSyncReceiveDecision.decide(context: legacyContext, applied: nil) == .legacy)
        let e = t.prepare(components: .init(context: legacyContext), trigger: .activation)!
        #expect(t.receive(ack: ack(e)) == .confirmed)
    }

    @Test func receiverRejectsStaleAndIncompatible() {
        let e = WatchSyncHandshake.Envelope(revision: 5, createdAt: Date(), components: a)
        let applied = WatchSyncAppliedRecord(revision: 7, snapshotID: UUID(), components: a)
        #expect(WatchSyncReceiveDecision.decide(context: e.contextEntries, applied: applied) == .stale)
        var ctx = e.contextEntries; ctx[WatchSyncHandshake.Key.protocolVersion] = 2
        #expect(WatchSyncReceiveDecision.decide(context: ctx, applied: nil) == .incompatible)
    }

    @Test func fingerprintsAreStableAndIgnoreUpdatedAt() {
        let c1: [String: Any] = ["settings.unit": "kg", "week.sets": 3, "week.updatedAt": Date(timeIntervalSince1970: 1)]
        let c2: [String: Any] = ["settings.unit": "kg", "week.sets": 3, "week.updatedAt": Date(timeIntervalSince1970: 99)]
        #expect(WatchSyncHandshake.Components(context: c1) == WatchSyncHandshake.Components(context: c2))
        let c3: [String: Any] = ["settings.unit": "lb", "week.sets": 3]
        #expect(WatchSyncHandshake.Components(context: c1).preferences != WatchSyncHandshake.Components(context: c3).preferences)
        #expect(WatchSyncHandshake.Components(context: c1).weekSummary == WatchSyncHandshake.Components(context: c3).weekSummary)
    }

    @Test func stateTextNeverLeaksIdentifiersAndCoversStates() {
        let states: [WatchSyncState] = [.notInstalled, .activating, .upToDate(confirmedAt: Date()),
            .queued(revision: 4242, since: Date()), .awaitingWatch(revision: 4242, since: Date()), .reconciling,
            .stale(lastConfirmedAt: nil), .failedRecoverably(reason: .writeFailed, lastConfirmedAt: nil)]
        for s in states {
            #expect(!s.summaryText.isEmpty)
            #expect(!s.accessibilityText(lastConfirmedAt: nil).contains("4242"))
        }
        #expect(WatchSyncState.queued(revision: 1, since: Date()).summaryText == "Pending")
        #expect(WatchSyncState.awaitingWatch(revision: 1, since: Date()).summaryText == "Waiting for Apple Watch")
    }
}
