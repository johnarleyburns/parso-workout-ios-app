import Foundation
import SwiftData
import Testing
import CadenceCore
@testable import CadenceFeatures

@MainActor
struct WatchCardioHistoryTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func cardio(id: UUID = UUID(), daysAgo: Double = 1, minutes: Double = 30,
                        origin: CardioRecordOrigin = .cladironRecorded, hk: UUID? = nil,
                        source: String? = nil, updated: Date? = nil, deleted: Bool = false) -> CardioWorkout {
        let start = now.addingTimeInterval(-daysAgo * 86_400)
        let row = CardioWorkout(id: id, type: .run, start: start, end: start.addingTimeInterval(minutes * 60),
                                distance: 5_000, activeEnergy: 400, avgHeartRate: 150, notes: "private note",
                                updatedAt: updated ?? start)
        row.healthKitWorkoutUUID = hk
        row.originValue = origin
        if let source {
            row.healthKitProvenance = HealthKitWorkoutProvenance(sourceName: source,
                                                                 sourceBundleIdentifier: "com.secret.bundle")
        }
        if deleted { row.deletedAt = now }
        return row
    }

    @Test func propertyListRoundTripIsPlistSafeAndLeaksNothing() throws {
        let rows = [cardio(origin: .healthKitImported, hk: UUID(), source: "Strava"), cardio(daysAgo: 2)]
        let snapshot = WatchCardioHistoryProjection.snapshot(from: rows, now: now)
        let context = snapshot.contextDict
        _ = try PropertyListSerialization.data(fromPropertyList: context, format: .binary, options: 0)
        #expect(WatchSync.CardioHistoryPayload(context: context) == .snapshot(snapshot))
        let keys = Set(snapshot.items.flatMap { $0.propertyList.keys })
        #expect(keys.isDisjoint(with: ["notes", "avgHeartRate", "activeEnergy", "route", "bundle", "source", "hr"]))
        let text = String(describing: context)
        #expect(!text.contains("com.secret.bundle") && !text.contains("private note"))
    }

    @Test func malformedSnapshotIsRejectedAtomically() {
        let good = WatchCardioHistoryProjection.snapshot(from: [cardio(), cardio(daysAgo: 2)], now: now).contextDict
        var rows = good[WatchSync.Key.cardioHistoryItems] as! [[String: Any]]
        rows[1]["id"] = "not-a-uuid"
        #expect(WatchSync.CardioHistoryPayload(context: [WatchSync.Key.cardioHistoryItems: rows]) == .malformed)
        rows = good[WatchSync.Key.cardioHistoryItems] as! [[String: Any]]
        rows[0]["distance"] = -4.0
        #expect(WatchSync.CardioHistoryPayload(context: [WatchSync.Key.cardioHistoryItems: rows]) == .malformed)
        rows = good[WatchSync.Key.cardioHistoryItems] as! [[String: Any]]
        rows[0]["v"] = 99
        #expect(WatchSync.CardioHistoryPayload(context: [WatchSync.Key.cardioHistoryItems: rows]) == .malformed)
        #expect(WatchSync.CardioHistoryPayload(context: [WatchSync.Key.cardioHistoryItems: "junk"]) == .malformed)
        #expect(WatchSync.CardioHistoryPayload(context: [WatchSync.Key.cardioHistoryItems: [rows[0], rows[0]]]) == .malformed)
        #expect(WatchSync.CardioHistoryPayload(context: [:]) == .absent)
        if case .snapshot(let empty) = WatchSync.CardioHistoryPayload(context: [WatchSync.Key.cardioHistoryItems: [[String: Any]]()]) {
            #expect(empty.items.isEmpty)
        } else { Issue.record("explicit empty must be a snapshot") }
    }

    @Test func limitsAgeSortAndDeterminism() {
        let rows = (0..<80).map { cardio(daysAgo: Double($0) * 0.5 + 0.1) } + [cardio(daysAgo: 120)]
        let snapshot = WatchCardioHistoryProjection.snapshot(from: rows, now: now)
        #expect(snapshot.liveItems.count == 60)
        #expect(snapshot.items.map(\.start) == snapshot.items.map(\.start).sorted(by: >))
        #expect(snapshot.fingerprint == WatchCardioHistoryProjection.snapshot(from: rows.reversed(), now: now).fingerprint)
        let aged = WatchCardioHistoryProjection.snapshot(from: [cardio(daysAgo: 89), cardio(daysAgo: 91)], now: now)
        #expect(aged.liveItems.count == 1)
    }

    @Test func tombstonesOnlyRemovePreviouslyMirroredRows() {
        let kept = cardio(), removed = cardio(daysAgo: 2, deleted: true), never = cardio(daysAgo: 3, deleted: true)
        let snapshot = WatchCardioHistoryProjection.snapshot(
            from: [kept, removed, never], previousLiveIDs: [kept.id, removed.id, UUID()], now: now)
        #expect(snapshot.liveItems.map(\.id) == [kept.id])
        #expect(snapshot.tombstones.count == 2)
        #expect(snapshot.tombstones.contains { $0.id == removed.id })
        #expect(!snapshot.tombstones.contains { $0.id == never.id })
    }

    @Test func importLabelOnlyOnImportedRowsAndSourceIdentityIsSingle() {
        let hk = UUID()
        let imported = cardio(origin: .healthKitImported, hk: hk, source: "Strava", updated: now)
        let dupe = cardio(origin: .healthKitImported, hk: hk, source: "Strava", updated: now.addingTimeInterval(-50))
        let fitness = cardio(daysAgo: 2, origin: .healthKitImported, hk: UUID(), source: "Fitness")
        let recorded = cardio(daysAgo: 3, source: "Strava")
        let snapshot = WatchCardioHistoryProjection.snapshot(from: [dupe, imported, fitness, recorded], now: now)
        #expect(snapshot.liveItems.count == 3)
        #expect(snapshot.liveItems.first { $0.id == imported.id }?.importLabel == "Imported from Strava")
        #expect(snapshot.liveItems.first { $0.id == fitness.id }?.importLabel == "Imported from Fitness")
        #expect(snapshot.liveItems.first { $0.id == recorded.id }?.importLabel == nil)
    }

    @Test func historyOnlyChangeAltersTheHandshakeComponent() {
        let a = WatchCardioHistoryProjection.snapshot(from: [cardio()], now: now)
        let b = WatchCardioHistoryProjection.snapshot(from: [cardio(), cardio(daysAgo: 2)], now: now)
        let base: [String: Any] = ["settings.unit": "kg"]
        let ca = WatchSyncHandshake.Components(context: base.merging(a.contextDict) { $1 })
        let cb = WatchSyncHandshake.Components(context: base.merging(b.contextDict) { $1 })
        let none = WatchSyncHandshake.Components(context: base)
        #expect(ca != cb)
        #expect(ca.preferences == cb.preferences && ca.todayPlan == cb.todayPlan)
        #expect(none.cardioHistory == "" && ca.cardioHistory != "")
        // updatedAt stamps never alter the fingerprint.
        var restamped = a.contextDict
        restamped[WatchSync.Key.cardioHistoryUpdatedAt] = Date()
        #expect(WatchSyncHandshake.Components(context: base.merging(restamped) { $1 }) == ca)
        // Envelope and ACK round-trip the component, and stripping removes it.
        let env = WatchSyncHandshake.Envelope(revision: 3, createdAt: now, components: cb)
        #expect(WatchSyncHandshake.Envelope(context: env.contextEntries)?.components.cardioHistory == cb.cardioHistory)
        #expect(WatchSyncHandshake.Envelope.stripping(env.contextEntries)[WatchSyncHandshake.Key.cardioHistoryRevision] == nil)
        #expect(WatchSyncHandshake.Ack(message: WatchSyncAppliedRecord(revision: 3, snapshotID: env.snapshotID, components: cb).ack.message)?.components?.cardioHistory == cb.cardioHistory)
    }

    @Test func legacyLedgerWithoutComponentDecodes() throws {
        let json = #"{"preferences":"a","customExercises":"b","todayPlan":"c","weekSummary":"d"}"#
        let c = try JSONDecoder().decode(WatchSyncHandshake.Components.self, from: Data(json.utf8))
        #expect(c.cardioHistory == "")
    }

    @Test func trackerDoesNotCoalesceAHistoryOnlyChange() {
        final class Store: WatchSyncLedgerStore { var l: WatchSyncLedger?; func load() -> WatchSyncLedger? { l }; func save(_ x: WatchSyncLedger) { l = x } }
        let tracker = WatchSyncTracker(store: Store(), clock: { self.now })
        var c = WatchSyncHandshake.Components(preferences: "p", customExercises: "e", todayPlan: "t", weekSummary: "w")
        #expect(tracker.prepare(components: c, trigger: .contentChanged) != nil)
        #expect(tracker.prepare(components: c, trigger: .contentChanged) == nil)
        c.cardioHistory = "abc"
        #expect(tracker.prepare(components: c, trigger: .contentChanged) != nil)
    }

    @Test func coordinatorWaitsForCardioHistoryAndRetriesCommitOnce() {
        var coordinator = WatchSyncCommitCoordinator()
        let env = WatchSyncHandshake.Envelope(revision: 1, createdAt: now,
            components: .init(preferences: "p", customExercises: "", todayPlan: "", weekSummary: "", cardioHistory: "h"))
        #expect(coordinator.accept(env, applied: nil, needsDurableExercises: false, needsDurableCardioHistory: true) == .awaitDurable)
        #expect(coordinator.durableStoreFinished(for: env, succeeded: false, applied: nil) == .failed)
        // Retry with the same revision: commits exactly once.
        #expect(coordinator.accept(env, applied: nil, needsDurableExercises: false, needsDurableCardioHistory: true) == .awaitDurable)
        guard case .commit(let record) = coordinator.durableStoreFinished(for: env, succeeded: true, applied: nil) else {
            Issue.record("expected commit"); return
        }
        #expect(record.revision == 1)
        #expect(coordinator.durableStoreFinished(for: env, succeeded: true, applied: record) == .discard)
        // A stale snapshot cannot overwrite newer applied state.
        let old = WatchSyncHandshake.Envelope(revision: 1, createdAt: now, components: env.components)
        #expect(coordinator.accept(old, applied: record, needsDurableExercises: false, needsDurableCardioHistory: true) == .discard)
    }

    private func container() throws -> ModelContainer {
        try ModelContainer(for: WatchCardioHistoryRecord.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func storeIsIdempotentExplicitEmptyClearsAndFailedSavePreservesProjection() throws {
        let context = ModelContext(try container())
        let first = WatchCardioHistoryProjection.snapshot(from: [cardio(), cardio(daysAgo: 2)], now: now)
        #expect(try WatchCardioHistoryStore.apply(first, in: context) == 2)
        #expect(try WatchCardioHistoryStore.apply(first, in: context) == 0)   // repeated snapshot

        struct Boom: Error {}
        let next = WatchCardioHistoryProjection.snapshot(from: [cardio(daysAgo: 5)], now: now)
        #expect(throws: Boom.self) { try WatchCardioHistoryStore.apply(next, in: context) { _ in throw Boom() } }
        let preserved = try context.fetch(FetchDescriptor<WatchCardioHistoryRecord>())
        #expect(Set(preserved.map(\.id)) == Set(first.liveItems.map(\.id)))

        #expect(try WatchCardioHistoryStore.apply(next, in: context) == 3)    // retry commits
        #expect(try context.fetch(FetchDescriptor<WatchCardioHistoryRecord>()).count == 1)
        try WatchCardioHistoryStore.apply(.init(items: [], updatedAt: now), in: context)
        #expect(try context.fetch(FetchDescriptor<WatchCardioHistoryRecord>()).isEmpty)
    }

    @Test func myWorkoutsMergesStrengthAndCardioWithOneLimitAndTypedSources() {
        let plan = WatchSync.TodayPlan(sessions: [.init(id: "a", kind: .strength, label: "Push")])
        var strength: [WatchMyWorkouts.HistoryInput] = []
        var cardioIn: [WatchMyWorkouts.CardioInput] = []
        for n in 0..<3 {
            let t = Double(n * 2)
            strength.append(.init(id: UUID(), title: "S", date: Date(timeIntervalSince1970: t), setCount: 4))
            let start = Date(timeIntervalSince1970: t + 1)
            cardioIn.append(.init(id: UUID(), title: "Run", type: "run", start: start,
                                  end: start.addingTimeInterval(1_800), distanceMeters: 5_000,
                                  importLabel: "Imported from a very long source name on a long device"))
        }
        let rows: [WatchMyWorkoutRow] = WatchMyWorkouts.rows(plan: plan, history: strength, cardio: cardioIn, historyLimit: 4)
        #expect(rows.count == 5)
        #expect(rows[0].status == WatchMyWorkoutRow.Status.planned)
        let dates: [Date] = rows.dropFirst().compactMap { $0.date }
        #expect(dates == dates.sorted(by: >))
        let cardioRow: WatchMyWorkoutRow = rows.first { $0.isCardio && $0.status == WatchMyWorkoutRow.Status.completed }!
        guard case .cardio = cardioRow.source else { Issue.record("cardio must not route as strength"); return }
        #expect(!cardioRow.showsSetCount)
        #expect(cardioRow.cardioSummary(distanceUnit: .kilometers) == "30 min · 5.0 km")
        #expect(cardioRow.originLabel?.hasPrefix("Imported from") == true)
        for row in rows where row.source.isStrengthForTest { #expect(row.showsSetCount) }
    }
}

private extension WatchMyWorkoutRow.Source {
    var isStrengthForTest: Bool { if case .strength = self { return true } else { return false } }
}
