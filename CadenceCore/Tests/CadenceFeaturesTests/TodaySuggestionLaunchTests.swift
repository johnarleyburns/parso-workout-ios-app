import Foundation
import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadencePhoneFeatures

/// Launch-order proof: the durable Today plan is restored before candidate
/// loading or generation; only a genuine miss loads candidates and generates.
struct TodaySuggestionLaunchTests {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
        func bump() { lock.lock(); n += 1; lock.unlock() }
    }
    private final class Clock: @unchecked Sendable {
        var date: Date
        init(_ d: Date) { date = d }
    }
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    private func day(_ d: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 3, day: d, hour: 9))!
    }
    private func url() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("launch-\(UUID().uuidString).json")
    }
    private func payload(_ title: String = "Push") -> TodaySuggestedPlanPayload {
        TodaySuggestedPlanPayload(EditablePlan(
            title: title, warmupMinutes: 5, cooldownMinutes: 3,
            exercises: [EditableExercise(
                name: "Bench Press",
                sets: [EditableSet(targetReps: 8, targetWeight: 60, loadMode: .straight),
                       EditableSet(targetReps: 6, targetWeight: 65, loadMode: .straight)],
                notes: "")],
            recommendationRationale: SuggestedWorkoutRationale(
                whyWorkout: "why",
                exercises: [SuggestedExerciseRationale(exerciseName: "Bench Press",
                                                       whyExercise: "a", whySetRep: "b")])))
    }

    /// Mirrors `HomeView.prepareTodaySuggestion`.
    private func launch(_ store: TodaySuggestedWorkoutCacheStore, key: String,
                        catalog: Counter, generator: Counter) async -> EditablePlan? {
        let gen = payload("Generated")
        let result = await TodaySuggestionLaunch.run(store: store, earlyKey: key) {
            catalog.bump()
            return await store.resolve(fingerprint: "full-" + key, earlyKey: key) {
                generator.bump(); return gen
            }
        }
        switch result {
        case .restored(let p): return p.makePlan()
        case .generated(let p): return p?.makePlan()
        }
    }

    @Test func restartRestoresBeforeCatalogAndGenerator() async {
        let u = url(); defer { try? FileManager.default.removeItem(at: u) }
        let now = day(10)
        let first = TodaySuggestedWorkoutCacheStore(fileURL: u, calendar: cal, now: { now })
        let catalog = Counter(), gen = Counter()
        let cold = await launch(first, key: "k", catalog: catalog, generator: gen)
        #expect(cold?.title == "Generated")
        #expect(catalog.value == 1); #expect(gen.value == 1)

        // Fresh process / recreated view: a new store over the same file.
        let second = TodaySuggestedWorkoutCacheStore(fileURL: u, calendar: cal, now: { now })
        let warm = await launch(second, key: "k", catalog: catalog, generator: gen)
        #expect(catalog.value == 1, "no catalog load on valid restore")
        #expect(gen.value == 1, "no generation on valid restore")
        #expect(warm?.title == "Generated")
        #expect(warm?.exercises.first?.name == "Bench Press")
        #expect(warm?.exercises.first?.sets.map(\.targetReps) == [8, 6])
        #expect(warm?.recommendationRationale?.whyWorkout == "why")
    }

    @Test func changedInputsDiscardAndRegenerateOnce() async {
        let d10 = day(10)
        let store = TodaySuggestedWorkoutCacheStore(fileURL: nil, calendar: cal, now: { d10 })
        let catalog = Counter(), gen = Counter()
        _ = await launch(store, key: "k1", catalog: catalog, generator: gen)
        _ = await launch(store, key: "k2", catalog: catalog, generator: gen)
        #expect(catalog.value == 2); #expect(gen.value == 2)
        let restored = await store.restoreEarly(earlyKey: "k2")
        #expect(restored != nil)
        let stale = await store.restoreEarly(earlyKey: "k1")
        #expect(stale == nil)
    }

    @Test func newDayAndCorruptAndOldSchemaMiss() async throws {
        let u = url(); defer { try? FileManager.default.removeItem(at: u) }
        let clock = Clock(day(10))
        let store = TodaySuggestedWorkoutCacheStore(fileURL: u, calendar: cal, now: { clock.date })
        await store.save(payload(), fingerprint: "f", earlyKey: "k")
        clock.date = day(11)
        let nextDay = await store.restoreEarly(earlyKey: "k")
        #expect(nextDay == nil)

        try Data("not json".utf8).write(to: u)
        let corrupt = TodaySuggestedWorkoutCacheStore(fileURL: u, calendar: cal, now: { clock.date })
        let c = await corrupt.restoreEarly(earlyKey: "k")
        #expect(c == nil)

        let old = #"{"schemaVersion":0,"dayKey":"x","fingerprint":"f","updatedAt":0,"plan":{}}"#
        try Data(old.utf8).write(to: u)
        let oldStore = TodaySuggestedWorkoutCacheStore(fileURL: u, calendar: cal, now: { clock.date })
        let o = await oldStore.restoreEarly(earlyKey: "k")
        #expect(o == nil)
    }

    @Test func recordWithoutEarlyKeyFallsThroughToFullPathAndUpgrades() async {
        let d10 = day(10)
        let store = TodaySuggestedWorkoutCacheStore(fileURL: nil, calendar: cal, now: { d10 })
        await store.save(payload(), fingerprint: "full-k")  // legacy record
        let early = await store.restoreEarly(earlyKey: "k")
        #expect(early == nil)
        let gen = Counter()
        let hit = await store.resolve(fingerprint: "full-k", earlyKey: "k") { gen.bump(); return nil }
        #expect(hit != nil); #expect(gen.value == 0)
        let upgraded = await store.restoreEarly(earlyKey: "k")
        #expect(upgraded != nil)
    }

    @Test func thisWeekDoesNotTouchTodayRecord() async {
        let d10 = day(10)
        // This Week uses its own store; Today's record survives Today → Week → Today.
        let today = TodaySuggestedWorkoutCacheStore(fileURL: nil, calendar: cal, now: { d10 })
        let week = TodaySuggestedWorkoutCacheStore(fileURL: nil, calendar: cal, now: { d10 })
        await today.save(payload(), fingerprint: "f", earlyKey: "k")
        await week.save(payload("Week"), fingerprint: "w", earlyKey: "wk")
        await week.invalidate()
        let back = await today.restoreEarly(earlyKey: "k")
        #expect(back?.title == "Push")
    }

    @Test func earlyKeyIsStableAndSensitive() {
        #expect(TodaySuggestedWorkoutEarlyKey.make(["a", "b"]) == TodaySuggestedWorkoutEarlyKey.make(["a", "b"]))
        #expect(TodaySuggestedWorkoutEarlyKey.make(["a", "b"]) != TodaySuggestedWorkoutEarlyKey.make(["ab"]))
    }
}
