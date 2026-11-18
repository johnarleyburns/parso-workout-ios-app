import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchWeekLocalOverlayStoreTests {
    private func makeStore(_ name: String = #function) -> WatchWeekLocalOverlayStore {
        let defaults = UserDefaults(suiteName: "WatchWeekLocalOverlayStoreTests.\(name)")!
        defaults.removePersistentDomain(forName: "WatchWeekLocalOverlayStoreTests.\(name)")
        return WatchWeekLocalOverlayStore(defaults: defaults, key: "overlays")
    }

    @Test func duplicateRecordWithSameIDDoesNotDuplicate() {
        let store = makeStore()
        let id = UUID()
        store.record(.init(id: id, weekKey: "2026-11-02", kind: .strength, sets: 3, completedAt: Date()))
        store.record(.init(id: id, weekKey: "2026-11-02", kind: .strength, sets: 5, completedAt: Date()))

        let overlays = store.overlays(forWeekKey: "2026-11-02")
        #expect(overlays.count == 1)
        #expect(overlays.first?.sets == 5)
    }

    @Test func acknowledgementRemovesExactlyOnceAndIsIdempotent() {
        let store = makeStore()
        let id = UUID()
        store.record(.init(id: id, weekKey: "2026-11-02", kind: .strength, sets: 3, completedAt: Date()))

        store.acknowledge(id: id)
        #expect(store.overlays(forWeekKey: "2026-11-02").isEmpty)

        // Re-acknowledging an already-removed (or unknown) ID is a safe no-op.
        store.acknowledge(id: id)
        store.acknowledge(id: UUID())
        #expect(store.overlays(forWeekKey: "2026-11-02").isEmpty)
    }

    @Test func malformedPersistedDataDecodesAsEmpty() {
        let defaults = UserDefaults(suiteName: "WatchWeekLocalOverlayStoreTests.malformed")!
        defaults.removePersistentDomain(forName: "WatchWeekLocalOverlayStoreTests.malformed")
        defaults.set(Data([0xFF, 0x00, 0x13]), forKey: "overlays")
        let store = WatchWeekLocalOverlayStore(defaults: defaults, key: "overlays")

        #expect(store.overlays(forWeekKey: "2026-11-02") == [])
    }

    @Test func watchRelaunchPreservesUnresolvedOverlay() {
        let defaults = UserDefaults(suiteName: "WatchWeekLocalOverlayStoreTests.relaunch")!
        defaults.removePersistentDomain(forName: "WatchWeekLocalOverlayStoreTests.relaunch")
        let first = WatchWeekLocalOverlayStore(defaults: defaults, key: "overlays")
        first.record(.init(id: UUID(), weekKey: "2026-11-02", kind: .cardio,
                           moderateEquivalentMinutes: 30, completedAt: Date()))

        // A fresh store instance over the same defaults simulates a Watch relaunch.
        let second = WatchWeekLocalOverlayStore(defaults: defaults, key: "overlays")
        #expect(second.overlays(forWeekKey: "2026-11-02").count == 1)
    }

    @Test func pruneKeepsOnlyTheGivenWeeks() {
        let store = makeStore()
        store.record(.init(id: UUID(), weekKey: "2026-10-19", kind: .strength, sets: 1, completedAt: Date()))
        store.record(.init(id: UUID(), weekKey: "2026-10-26", kind: .strength, sets: 1, completedAt: Date()))
        store.record(.init(id: UUID(), weekKey: "2026-11-02", kind: .strength, sets: 1, completedAt: Date()))

        store.prune(keepingWeekKeys: ["2026-10-26", "2026-11-02"])

        #expect(store.overlays(forWeekKey: "2026-10-19").isEmpty)
        #expect(store.overlays(forWeekKey: "2026-10-26").count == 1)
        #expect(store.overlays(forWeekKey: "2026-11-02").count == 1)
    }
}
