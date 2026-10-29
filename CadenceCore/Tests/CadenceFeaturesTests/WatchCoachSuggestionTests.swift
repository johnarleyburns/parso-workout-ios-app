import XCTest
@testable import CadenceFeatures

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

final class WatchCoachSuggestionTests: XCTestCase {
    private typealias F = CoachSuggestionFixtures
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private let noon = Date(timeIntervalSince1970: 1_799_971_200 + 43_200)

    private func envelope(issued: Date? = nil, catalogDrop: Int = 0) -> WatchCoachSuggestionEnvelope {
        let issued = issued ?? noon
        let request = F.request(candidates: Array(F.catalog.dropLast(catalogDrop)), asOf: issued)
        let snap = CoachSuggestionSnapshotBuilder.make(request: request, generatedAt: issued, calendar: cal)
        return .make(snapshot: snap, issuedAt: issued, calendar: cal)
    }

    func testContextRoundTripKeepsExactEnvelope() throws {
        let e = envelope()
        let ctx = try WatchSync.contextDict(e)
        XCTAssertTrue(ctx[WatchSync.Key.coachSuggestionSnapshot] is Data)
        XCTAssertEqual(ctx[WatchSync.Key.coachSuggestionSnapshotUpdatedAt] as? Date, e.issuedAt)
        XCTAssertEqual(WatchCoachSuggestionPayload(context: ctx), .envelope(e))
        let incoming = WatchSync.IncomingContext.from(context: ctx, applyingTo: .init())
        XCTAssertEqual(incoming.coachSuggestion, .envelope(e))
    }

    func testMalformedAndUnknownSchemaRejected() throws {
        XCTAssertEqual(WatchCoachSuggestionPayload(context: [WatchSync.Key.coachSuggestionSnapshot: Data([1, 2])]), .invalid)
        XCTAssertEqual(WatchCoachSuggestionPayload(context: [WatchSync.Key.coachSuggestionSnapshot: "x"]), .invalid)
        var top = try JSONSerialization.jsonObject(with: envelope().encoded()) as! [String: Any]
        top["schemaVersion"] = 2
        XCTAssertEqual(WatchCoachSuggestionEnvelope.decode(try JSONSerialization.data(withJSONObject: top)),
                       .failure(.unsupportedSchema(2)))
        // Nested snapshot schema.
        var bad = try JSONSerialization.jsonObject(with: envelope().encoded()) as! [String: Any]
        var snap = bad["snapshot"] as! [String: Any]; snap["schemaVersion"] = 9; bad["snapshot"] = snap
        let badData = try JSONSerialization.data(withJSONObject: bad)
        XCTAssertEqual(WatchCoachSuggestionEnvelope.decode(badData), .failure(.unsupportedSchema(9)))
    }

    func testNewerSupersedesAndLateOlderNeverOverwrites() {
        let store = MemoryCoachStore()
        let c = WatchCoachSuggestionCoordinator(store: store)
        let older = envelope(issued: noon, catalogDrop: 1)
        let newer = envelope(issued: noon.addingTimeInterval(600))
        XCTAssertEqual(c.apply(.envelope(newer), isHandshakeSnapshot: true), .applied)
        XCTAssertEqual(c.apply(.envelope(older), isHandshakeSnapshot: true), .ignored)
        XCTAssertEqual(c.current, newer)
        XCTAssertEqual(WatchCoachSuggestionCoordinator(store: store).current, newer)
    }

    func testRemovalIsAppliedAndLegacyContextDoesNotRemove() {
        let c = WatchCoachSuggestionCoordinator(store: MemoryCoachStore())
        _ = c.apply(.envelope(envelope()), isHandshakeSnapshot: true)
        XCTAssertEqual(c.apply(.absent, isHandshakeSnapshot: false), .ignored)
        XCTAssertNotNil(c.current)
        XCTAssertEqual(c.apply(.absent, isHandshakeSnapshot: true), .removed)
        XCTAssertNil(c.current)
    }

    func testFreshProcessReloadReturnsExactEnvelopeOffline() {
        let store = MemoryCoachStore()
        let e = envelope()
        _ = WatchCoachSuggestionCoordinator(store: store).apply(.envelope(e), isHandshakeSnapshot: true)
        let reloaded = WatchCoachSuggestionCoordinator(store: store)
        XCTAssertEqual(reloaded.current, e)
        XCTAssertEqual(reloaded.startable(now: noon.addingTimeInterval(60)), e)
    }

    func testFailedWritePreservesPriorAndRejectsAck() {
        let store = MemoryCoachStore()
        let c = WatchCoachSuggestionCoordinator(store: store)
        let prior = envelope()
        _ = c.apply(.envelope(prior), isHandshakeSnapshot: true)
        store.failWrites = true
        XCTAssertEqual(c.apply(.envelope(envelope(issued: noon.addingTimeInterval(60), catalogDrop: 1)), isHandshakeSnapshot: true), .rejected)
        XCTAssertEqual(c.apply(.absent, isHandshakeSnapshot: true), .rejected)
        XCTAssertEqual(c.apply(.invalid, isHandshakeSnapshot: true), .rejected)
        XCTAssertEqual(c.current, prior)
        XCTAssertEqual(WatchCoachSuggestionCoordinator(store: store).current, prior)
    }

    func testWatchCompletionInvalidatesImmediatelyAndBlocksResurrection() {
        let store = MemoryCoachStore()
        let c = WatchCoachSuggestionCoordinator(store: store)
        let e = envelope()
        _ = c.apply(.envelope(e), isHandshakeSnapshot: true)
        let done = noon.addingTimeInterval(300)
        c.invalidate(now: done)
        XCTAssertNil(c.current)
        XCTAssertNil(c.startable(now: done))
        XCTAssertNil(store.data)
        // The phone's pre-completion envelope arriving late cannot resurrect it.
        XCTAssertEqual(c.apply(.envelope(e), isHandshakeSnapshot: true), .ignored)
        // Even if deletion failed, a reload honours the invalidation marker.
        store.data = try? e.encoded()
        XCTAssertNil(WatchCoachSuggestionCoordinator(store: store).current)
        // A refresh issued after completion is accepted.
        let fresh = envelope(issued: done.addingTimeInterval(30), catalogDrop: 1)
        XCTAssertEqual(c.apply(.envelope(fresh), isHandshakeSnapshot: true), .applied)
    }

    func testDayBoundaryAndClockSkewFailClosed() {
        let e = envelope()
        XCTAssertEqual(e.expiresAt, cal.startOfDay(for: noon).addingTimeInterval(86_400))
        XCTAssertEqual(e.sourceRevision, e.snapshot.fingerprint)
        XCTAssertTrue(e.isStartable(now: noon))
        XCTAssertTrue(e.isStartable(now: e.expiresAt.addingTimeInterval(-1)))
        XCTAssertFalse(e.isStartable(now: e.expiresAt))
        XCTAssertFalse(e.isStartable(now: e.expiresAt.addingTimeInterval(3600)))
        // Watch clock far behind the phone: issued in the future.
        XCTAssertFalse(e.isStartable(now: noon.addingTimeInterval(-3600)))
        let inverted = WatchCoachSuggestionEnvelope(snapshot: e.snapshot, issuedAt: noon, expiresAt: noon.addingTimeInterval(-1), sourceRevision: "x")
        XCTAssertFalse(inverted.isStartable(now: noon))
        let tooLong = WatchCoachSuggestionEnvelope(snapshot: e.snapshot, issuedAt: noon, expiresAt: noon.addingTimeInterval(7 * 86_400), sourceRevision: "x")
        XCTAssertFalse(tooLong.isStartable(now: noon))
    }

    func testExpiredEnvelopeRetainedButNotStartable() {
        let c = WatchCoachSuggestionCoordinator(store: MemoryCoachStore())
        let e = envelope()
        _ = c.apply(.envelope(e), isHandshakeSnapshot: true)
        let tomorrow = e.expiresAt.addingTimeInterval(10)
        XCTAssertEqual(c.current, e)
        XCTAssertNil(c.startable(now: tomorrow))
    }

    func testHandshakeComponentsTrackSnapshotChangeExpiryAndRemoval() throws {
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
        XCTAssertEqual(c1, try comps(e1))
        XCTAssertNotEqual(c1.coachSuggestion, try comps(e2).coachSuggestion)
        XCTAssertNotEqual(c1.coachSuggestion, try comps(expiryChanged).coachSuggestion)
        XCTAssertEqual(try comps(nil).coachSuggestion, "")
        XCTAssertNotEqual(c1, try comps(nil))
        XCTAssertEqual(c1.preferences, try comps(nil).preferences)
        // Components round-trip through the envelope entries and the Ack message.
        let env = WatchSyncHandshake.Envelope(revision: 1, createdAt: noon, components: c1)
        XCTAssertEqual(WatchSyncHandshake.Envelope(context: env.contextEntries)?.components, c1)
        XCTAssertEqual(WatchSyncHandshake.Ack(message: WatchSyncHandshake.Ack(revision: 1, snapshotID: env.snapshotID, components: c1).message)?.components, c1)
        XCTAssertNil(WatchSyncHandshake.Envelope.stripping(env.contextEntries)[WatchSyncHandshake.Key.coachSuggestionRevision])
    }

    func testLegacyLedgerComponentsStillDecode() throws {
        let json = #"{"preferences":"a","customExercises":"b","todayPlan":"c","weekSummary":"d"}"#
        let c = try JSONDecoder().decode(WatchSyncHandshake.Components.self, from: Data(json.utf8))
        XCTAssertEqual(c.coachSuggestion, "")
    }
}
