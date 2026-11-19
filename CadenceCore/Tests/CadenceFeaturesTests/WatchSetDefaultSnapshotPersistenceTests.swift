import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchSetDefaultSnapshotPersistenceTests {
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

    @Test func contextDecodesValidSnapshot() {
        let snap = snapshot(at: 100)
        let ctx = WatchSync.IncomingContext.from(
            context: [WatchSync.Key.setDefaultSnapshot: snap.propertyList], applyingTo: .init())
        #expect(ctx.setDefaultSnapshot == snap)
        let store = WatchSetDefaultSnapshotPersistence(defaults: defaults())
        #expect(store.replaceIfNewer(ctx.setDefaultSnapshot!) == .replaced)
        #expect(store.load() == snap)
    }

    @Test func malformedAndFutureVersionAreNilAndDoNotReplace() {
        let store = WatchSetDefaultSnapshotPersistence(defaults: defaults())
        let valid = snapshot(at: 100)
        #expect(store.replaceIfNewer(valid) == .replaced)
        var future = valid.propertyList
        future["version"] = 99
        future["generatedAt"] = 500.0
        for payload: Any in [future, "junk", ["version": 1]] as [Any] {
            let ctx = WatchSync.IncomingContext.from(
                context: [WatchSync.Key.setDefaultSnapshot: payload], applyingTo: .init())
            #expect(ctx.setDefaultSnapshot == nil)
        }
        #expect(store.load() == valid)
    }

    @Test func olderAndEqualNeverReplaceNewer() {
        let store = WatchSetDefaultSnapshotPersistence(defaults: defaults())
        let newer = snapshot(at: 200)
        #expect(store.replaceIfNewer(newer) == .replaced)
        #expect(store.replaceIfNewer(snapshot(at: 100, kg: 10)) == .keptExisting)
        #expect(store.replaceIfNewer(snapshot(at: 200, kg: 10)) == .keptExisting)
        #expect(store.load() == newer)
        #expect(store.replaceIfNewer(snapshot(at: 300, kg: 70)) == .replaced)
        #expect(store.load()?.generatedAt == Date(timeIntervalSince1970: 300))
    }

    @Test func corruptStoredDataIsDiscarded() {
        let d = defaults()
        d.set(Data("not json".utf8), forKey: WatchSetDefaultSnapshotPersistence.defaultsKey)
        let store = WatchSetDefaultSnapshotPersistence(defaults: d)
        #expect(store.load() == nil)
        #expect(d.data(forKey: WatchSetDefaultSnapshotPersistence.defaultsKey) == nil)
        #expect(store.replaceIfNewer(snapshot(at: 1)) == .replaced)
    }

    @Test func roundTripPreservesKgAndPerformerIDs() {
        let d = defaults()
        let snap = snapshot(at: 100, kg: 61.234)
        _ = WatchSetDefaultSnapshotPersistence(defaults: d).replaceIfNewer(snap)
        let loaded = WatchSetDefaultSnapshotPersistence(defaults: d).load()
        #expect(loaded?.performers.map(\.id) == [pid])
        #expect(loaded?.performers.first?.exercises.first?.samples.first?.weightKg == 61.234)
        #expect(loaded?.performers.first?.exercises.first?.firstWorkingWeightKg == 61.234)
    }

    @Test func snapshotOnlyChangeAltersHandshakeFingerprint() {
        let a = WatchSyncHandshake.Components(context: [WatchSync.Key.setDefaultSnapshot: snapshot(at: 100).propertyList])
        let b = WatchSyncHandshake.Components(context: [WatchSync.Key.setDefaultSnapshot: snapshot(at: 200).propertyList])
        let none = WatchSyncHandshake.Components(context: [:])
        #expect(a != b)
        #expect(a != none)
    }
}
