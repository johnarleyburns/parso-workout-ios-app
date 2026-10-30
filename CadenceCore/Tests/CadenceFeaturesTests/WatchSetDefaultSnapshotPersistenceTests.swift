import XCTest
@testable import CadenceFeatures

final class WatchSetDefaultSnapshotPersistenceTests: XCTestCase {
    private let pid = "5B2C3E5A-1111-4222-8333-444455556666"

    private func defaults() -> UserDefaults {
        let name = "snapshot-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func snapshot(at t: TimeInterval, kg: Double = 62.5) -> WatchSetDefaultSnapshot {
        WatchSetDefaultSnapshot(generatedAt: Date(timeIntervalSince1970: t), performers: [
            .init(id: pid, displayName: "P", exercises: [
                .init(id: "Bench Press", displayName: "Bench Press", repLadders: [[5, 5]],
                      samples: [.init(weightKg: kg, reps: 5)], firstWorkingWeightKg: kg)],
                  generalRepLadders: [[8]])])
    }

    func testContextDecodesValidSnapshot() {
        let snap = snapshot(at: 100)
        let ctx = WatchSync.IncomingContext.from(
            context: [WatchSync.Key.setDefaultSnapshot: snap.propertyList], applyingTo: .init())
        XCTAssertEqual(ctx.setDefaultSnapshot, snap)
        let store = WatchSetDefaultSnapshotPersistence(defaults: defaults())
        XCTAssertEqual(store.replaceIfNewer(ctx.setDefaultSnapshot!), .replaced)
        XCTAssertEqual(store.load(), snap)
    }

    func testMalformedAndFutureVersionAreNilAndDoNotReplace() {
        let store = WatchSetDefaultSnapshotPersistence(defaults: defaults())
        let valid = snapshot(at: 100)
        XCTAssertEqual(store.replaceIfNewer(valid), .replaced)
        var future = valid.propertyList
        future["version"] = 99
        future["generatedAt"] = 500.0
        for payload: Any in [future, "junk", ["version": 1]] as [Any] {
            let ctx = WatchSync.IncomingContext.from(
                context: [WatchSync.Key.setDefaultSnapshot: payload], applyingTo: .init())
            XCTAssertNil(ctx.setDefaultSnapshot)
        }
        XCTAssertEqual(store.load(), valid)
    }

    func testOlderAndEqualNeverReplaceNewer() {
        let store = WatchSetDefaultSnapshotPersistence(defaults: defaults())
        let newer = snapshot(at: 200)
        XCTAssertEqual(store.replaceIfNewer(newer), .replaced)
        XCTAssertEqual(store.replaceIfNewer(snapshot(at: 100, kg: 10)), .keptExisting)
        XCTAssertEqual(store.replaceIfNewer(snapshot(at: 200, kg: 10)), .keptExisting)
        XCTAssertEqual(store.load(), newer)
        XCTAssertEqual(store.replaceIfNewer(snapshot(at: 300, kg: 70)), .replaced)
        XCTAssertEqual(store.load()?.generatedAt, Date(timeIntervalSince1970: 300))
    }

    func testCorruptStoredDataIsDiscarded() {
        let d = defaults()
        d.set(Data("not json".utf8), forKey: WatchSetDefaultSnapshotPersistence.defaultsKey)
        let store = WatchSetDefaultSnapshotPersistence(defaults: d)
        XCTAssertNil(store.load())
        XCTAssertNil(d.data(forKey: WatchSetDefaultSnapshotPersistence.defaultsKey))
        XCTAssertEqual(store.replaceIfNewer(snapshot(at: 1)), .replaced)
    }

    func testRoundTripPreservesKgAndPerformerIDs() {
        let d = defaults()
        let snap = snapshot(at: 100, kg: 61.234)
        _ = WatchSetDefaultSnapshotPersistence(defaults: d).replaceIfNewer(snap)
        let loaded = WatchSetDefaultSnapshotPersistence(defaults: d).load()
        XCTAssertEqual(loaded?.performers.map(\.id), [pid])
        XCTAssertEqual(loaded?.performers.first?.exercises.first?.samples.first?.weightKg, 61.234)
        XCTAssertEqual(loaded?.performers.first?.exercises.first?.firstWorkingWeightKg, 61.234)
    }

    func testSnapshotOnlyChangeAltersHandshakeFingerprint() {
        let a = WatchSyncHandshake.Components(context: [WatchSync.Key.setDefaultSnapshot: snapshot(at: 100).propertyList])
        let b = WatchSyncHandshake.Components(context: [WatchSync.Key.setDefaultSnapshot: snapshot(at: 200).propertyList])
        let none = WatchSyncHandshake.Components(context: [:])
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a, none)
    }
}
