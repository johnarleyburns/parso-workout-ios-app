import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadencePhoneFeatures

private final class MemoryCoachStore: WatchCoachSuggestionStoring {
    struct Failure: Error {}
    var data: Data?
    var invalidatedAt: Date?
    var failWrites = false
    func loadData() -> Data? { data }
    func saveData(_ data: Data) throws { if failWrites { throw Failure() }; self.data = data }
    func deleteData() throws { if failWrites { throw Failure() }; data = nil }
    func loadInvalidatedAt() -> Date? { invalidatedAt }
    func saveInvalidatedAt(_ date: Date) { invalidatedAt = date }
}

struct WatchCoachSuggestionTests {
    private typealias F = CoachSuggestionFixtures
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private let noon = Date(timeIntervalSince1970: 1_799_971_200 + 43_200)

    private func envelope(issued: Date? = nil, catalogDrop: Int = 0) -> WatchCoachSuggestionEnvelope {
        let issued = issued ?? noon
        let request = F.request(candidates: Array(F.catalog.dropLast(catalogDrop)), asOf: issued)
        let snap = CoachSuggestionSnapshotBuilder.make(request: request, generatedAt: issued, calendar: cal)
        return .make(snapshot: snap, issuedAt: issued, calendar: cal)
    }

    @Test func contextRoundTripKeepsExactEnvelope() throws {
        let e = envelope()
        let ctx = try WatchSync.contextDict(e)
        #expect(ctx[WatchSync.Key.coachSuggestionSnapshot] is Data)
        #expect(ctx[WatchSync.Key.coachSuggestionSnapshotUpdatedAt] as? Date == e.issuedAt)
        #expect(WatchCoachSuggestionPayload(context: ctx) == .envelope(e))
        let incoming = WatchSync.IncomingContext.from(context: ctx, applyingTo: .init())
        #expect(incoming.coachSuggestion == .envelope(e))
    }

    @Test func malformedAndUnknownSchemaRejected() throws {
        #expect(WatchCoachSuggestionPayload(context: [WatchSync.Key.coachSuggestionSnapshot: Data([1, 2])]) == .invalid)
        #expect(WatchCoachSuggestionPayload(context: [WatchSync.Key.coachSuggestionSnapshot: "x"]) == .invalid)
        var top = try JSONSerialization.jsonObject(with: envelope().encoded()) as! [String: Any]
        top["schemaVersion"] = 2
        #expect(WatchCoachSuggestionEnvelope.decode(try JSONSerialization.data(withJSONObject: top)) ==
                       .failure(.unsupportedSchema(2)))
        // Nested snapshot schema.
        var bad = try JSONSerialization.jsonObject(with: envelope().encoded()) as! [String: Any]
        var snap = bad["snapshot"] as! [String: Any]; snap["schemaVersion"] = 9; bad["snapshot"] = snap
        let badData = try JSONSerialization.data(withJSONObject: bad)
        #expect(WatchCoachSuggestionEnvelope.decode(badData) == .failure(.unsupportedSchema(9)))
    }

    @Test func newerSupersedesAndLateOlderNeverOverwrites() {
        let store = MemoryCoachStore()
        let c = WatchCoachSuggestionCoordinator(store: store)
        let older = envelope(issued: noon, catalogDrop: 1)
        let newer = envelope(issued: noon.addingTimeInterval(600))
        #expect(c.apply(.envelope(newer), isHandshakeSnapshot: true) == .applied)
        #expect(c.apply(.envelope(older), isHandshakeSnapshot: true) == .ignored)
        #expect(c.current == newer)
        #expect(WatchCoachSuggestionCoordinator(store: store).current == newer)
    }

    @Test func removalIsAppliedAndLegacyContextDoesNotRemove() {
        let c = WatchCoachSuggestionCoordinator(store: MemoryCoachStore())
        _ = c.apply(.envelope(envelope()), isHandshakeSnapshot: true)
        #expect(c.apply(.absent, isHandshakeSnapshot: false) == .ignored)
        #expect(c.current != nil)
        #expect(c.apply(.absent, isHandshakeSnapshot: true) == .removed)
        #expect(c.current == nil)
    }

    @Test func freshProcessReloadReturnsExactEnvelopeOffline() {
        let store = MemoryCoachStore()
        let e = envelope()
        _ = WatchCoachSuggestionCoordinator(store: store).apply(.envelope(e), isHandshakeSnapshot: true)
        let reloaded = WatchCoachSuggestionCoordinator(store: store)
        #expect(reloaded.current == e)
        #expect(reloaded.startable(now: noon.addingTimeInterval(60)) == e)
    }

    @Test func failedWritePreservesPriorAndRejectsAck() {
        let store = MemoryCoachStore()
        let c = WatchCoachSuggestionCoordinator(store: store)
        let prior = envelope()
        _ = c.apply(.envelope(prior), isHandshakeSnapshot: true)
        store.failWrites = true
        #expect(c.apply(.envelope(envelope(issued: noon.addingTimeInterval(60), catalogDrop: 1)), isHandshakeSnapshot: true) == .rejected)
        #expect(c.apply(.absent, isHandshakeSnapshot: true) == .rejected)
        #expect(c.apply(.invalid, isHandshakeSnapshot: true) == .rejected)
        #expect(c.current == prior)
        #expect(WatchCoachSuggestionCoordinator(store: store).current == prior)
    }

    @Test func watchCompletionInvalidatesImmediatelyAndBlocksResurrection() {
        let store = MemoryCoachStore()
        let c = WatchCoachSuggestionCoordinator(store: store)
        let e = envelope()
        _ = c.apply(.envelope(e), isHandshakeSnapshot: true)
        let done = noon.addingTimeInterval(300)
        c.invalidate(now: done)
        #expect(c.current == nil)
        #expect(c.startable(now: done) == nil)
        #expect(store.data == nil)
        // The phone's pre-completion envelope arriving late cannot resurrect it.
        #expect(c.apply(.envelope(e), isHandshakeSnapshot: true) == .ignored)
        // Even if deletion failed, a reload honours the invalidation marker.
        store.data = try? e.encoded()
        #expect(WatchCoachSuggestionCoordinator(store: store).current == nil)
        // A refresh issued after completion is accepted.
        let fresh = envelope(issued: done.addingTimeInterval(30), catalogDrop: 1)
        #expect(c.apply(.envelope(fresh), isHandshakeSnapshot: true) == .applied)
    }

    @Test func dayBoundaryAndClockSkewFailClosed() {
        let e = envelope()
        #expect(e.expiresAt == cal.startOfDay(for: noon).addingTimeInterval(86_400))
        #expect(e.sourceRevision == e.snapshot.fingerprint)
        #expect(e.isStartable(now: noon))
        #expect(e.isStartable(now: e.expiresAt.addingTimeInterval(-1)))
        #expect(!e.isStartable(now: e.expiresAt))
        #expect(!e.isStartable(now: e.expiresAt.addingTimeInterval(3600)))
        // Watch clock far behind the phone: issued in the future.
        #expect(!e.isStartable(now: noon.addingTimeInterval(-3600)))
        let inverted = WatchCoachSuggestionEnvelope(snapshot: e.snapshot, issuedAt: noon, expiresAt: noon.addingTimeInterval(-1), sourceRevision: "x")
        #expect(!inverted.isStartable(now: noon))
        let tooLong = WatchCoachSuggestionEnvelope(snapshot: e.snapshot, issuedAt: noon, expiresAt: noon.addingTimeInterval(7 * 86_400), sourceRevision: "x")
        #expect(!tooLong.isStartable(now: noon))
    }

    @Test func expiredEnvelopeRetainedButNotStartable() {
        let c = WatchCoachSuggestionCoordinator(store: MemoryCoachStore())
        let e = envelope()
        _ = c.apply(.envelope(e), isHandshakeSnapshot: true)
        let tomorrow = e.expiresAt.addingTimeInterval(10)
        #expect(c.current == e)
        #expect(c.startable(now: tomorrow) == nil)
    }

    @Test func handshakeComponentsTrackSnapshotChangeExpiryAndRemoval() throws {
        let base: [String: Any] = [WatchSync.Key.unit: "kg"]
        func comps(_ e: WatchCoachSuggestionEnvelope?) throws -> WatchSyncHandshake.Components {
            var ctx = base
            if let e { ctx.merge(try WatchSync.contextDict(e)) { _, n in n } }
            return WatchSyncHandshake.Components(context: ctx)
        }
        let e1 = envelope(), e2 = envelope(catalogDrop: 1)
        let expiryChanged = WatchCoachSuggestionEnvelope(snapshot: e1.snapshot, issuedAt: e1.issuedAt,
                                                         expiresAt: e1.expiresAt.addingTimeInterval(3600), sourceRevision: e1.sourceRevision)
        let c1 = try comps(e1)
        let c1Again = try comps(e1)
        let c2 = try comps(e2)
        let cExpiryChanged = try comps(expiryChanged)
        let cNil = try comps(nil)
        #expect(c1 == c1Again)
        #expect(c1.coachSuggestion != c2.coachSuggestion)
        #expect(c1.coachSuggestion != cExpiryChanged.coachSuggestion)
        #expect(cNil.coachSuggestion == "")
        #expect(c1 != cNil)
        #expect(c1.preferences == cNil.preferences)
        // Components round-trip through the envelope entries and the Ack message.
        let env = WatchSyncHandshake.Envelope(revision: 1, createdAt: noon, components: c1)
        #expect(WatchSyncHandshake.Envelope(context: env.contextEntries)?.components == c1)
        #expect(WatchSyncHandshake.Ack(message: WatchSyncHandshake.Ack(revision: 1, snapshotID: env.snapshotID, components: c1).message)?.components == c1)
        #expect(WatchSyncHandshake.Envelope.stripping(env.contextEntries)[WatchSyncHandshake.Key.coachSuggestionRevision] == nil)
    }

    @Test func legacyLedgerComponentsStillDecode() throws {
        let json = #"{"preferences":"a","customExercises":"b","todayPlan":"c","weekSummary":"d"}"#
        let c = try JSONDecoder().decode(WatchSyncHandshake.Components.self, from: Data(json.utf8))
        #expect(c.coachSuggestion == "")
    }
}
