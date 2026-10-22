import XCTest
import CadenceCore
@testable import CadenceFeatures

/// Launch-order proof: the durable Today plan is restored before candidate
/// loading or generation; only a genuine miss loads candidates and generates.
final class TodaySuggestionLaunchTests: XCTestCase {
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

    func testRestartRestoresBeforeCatalogAndGenerator() async {
        let u = url(); defer { try? FileManager.default.removeItem(at: u) }
        let now = day(10)
        let first = TodaySuggestedWorkoutCacheStore(fileURL: u, calendar: cal, now: { now })
        let catalog = Counter(), gen = Counter()
        let cold = await launch(first, key: "k", catalog: catalog, generator: gen)
        XCTAssertEqual(cold?.title, "Generated")
        XCTAssertEqual(catalog.value, 1); XCTAssertEqual(gen.value, 1)

        // Fresh process / recreated view: a new store over the same file.
        let second = TodaySuggestedWorkoutCacheStore(fileURL: u, calendar: cal, now: { now })
        let warm = await launch(second, key: "k", catalog: catalog, generator: gen)
        XCTAssertEqual(catalog.value, 1, "no catalog load on valid restore")
        XCTAssertEqual(gen.value, 1, "no generation on valid restore")
        XCTAssertEqual(warm?.title, "Generated")
        XCTAssertEqual(warm?.exercises.first?.name, "Bench Press")
        XCTAssertEqual(warm?.exercises.first?.sets.map(\.targetReps), [8, 6])
        XCTAssertEqual(warm?.recommendationRationale?.whyWorkout, "why")
    }

    func testChangedInputsDiscardAndRegenerateOnce() async {
        let d10 = day(10)
        let store = TodaySuggestedWorkoutCacheStore(fileURL: nil, calendar: cal, now: { d10 })
        let catalog = Counter(), gen = Counter()
        _ = await launch(store, key: "k1", catalog: catalog, generator: gen)
        _ = await launch(store, key: "k2", catalog: catalog, generator: gen)
        XCTAssertEqual(catalog.value, 2); XCTAssertEqual(gen.value, 2)
        let restored = await store.restoreEarly(earlyKey: "k2")
        XCTAssertNotNil(restored)
        let stale = await store.restoreEarly(earlyKey: "k1")
        XCTAssertNil(stale)
    }

    func testNewDayAndCorruptAndOldSchemaMiss() async throws {
        let u = url(); defer { try? FileManager.default.removeItem(at: u) }
        let clock = Clock(day(10))
        let store = TodaySuggestedWorkoutCacheStore(fileURL: u, calendar: cal, now: { clock.date })
        await store.save(payload(), fingerprint: "f", earlyKey: "k")
        clock.date = day(11)
        let nextDay = await store.restoreEarly(earlyKey: "k")
        XCTAssertNil(nextDay)

        try Data("not json".utf8).write(to: u)
        let corrupt = TodaySuggestedWorkoutCacheStore(fileURL: u, calendar: cal, now: { clock.date })
        let c = await corrupt.restoreEarly(earlyKey: "k")
        XCTAssertNil(c)

        let old = #"{"schemaVersion":0,"dayKey":"x","fingerprint":"f","updatedAt":0,"plan":{}}"#
        try Data(old.utf8).write(to: u)
        let oldStore = TodaySuggestedWorkoutCacheStore(fileURL: u, calendar: cal, now: { clock.date })
        let o = await oldStore.restoreEarly(earlyKey: "k")
        XCTAssertNil(o)
    }

    func testRecordWithoutEarlyKeyFallsThroughToFullPathAndUpgrades() async {
        let d10 = day(10)
        let store = TodaySuggestedWorkoutCacheStore(fileURL: nil, calendar: cal, now: { d10 })
        await store.save(payload(), fingerprint: "full-k")  // legacy record
        let early = await store.restoreEarly(earlyKey: "k")
        XCTAssertNil(early)
        let gen = Counter()
        let hit = await store.resolve(fingerprint: "full-k", earlyKey: "k") { gen.bump(); return nil }
        XCTAssertNotNil(hit); XCTAssertEqual(gen.value, 0)
        let upgraded = await store.restoreEarly(earlyKey: "k")
        XCTAssertNotNil(upgraded)
    }

    func testThisWeekDoesNotTouchTodayRecord() async {
        let d10 = day(10)
        // This Week uses its own store; Today's record survives Today → Week → Today.
        let today = TodaySuggestedWorkoutCacheStore(fileURL: nil, calendar: cal, now: { d10 })
        let week = TodaySuggestedWorkoutCacheStore(fileURL: nil, calendar: cal, now: { d10 })
        await today.save(payload(), fingerprint: "f", earlyKey: "k")
        await week.save(payload("Week"), fingerprint: "w", earlyKey: "wk")
        await week.invalidate()
        let back = await today.restoreEarly(earlyKey: "k")
        XCTAssertEqual(back?.title, "Push")
    }

    func testEarlyKeyIsStableAndSensitive() {
        XCTAssertEqual(TodaySuggestedWorkoutEarlyKey.make(["a", "b"]), TodaySuggestedWorkoutEarlyKey.make(["a", "b"]))
        XCTAssertNotEqual(TodaySuggestedWorkoutEarlyKey.make(["a", "b"]), TodaySuggestedWorkoutEarlyKey.make(["ab"]))
    }
}
