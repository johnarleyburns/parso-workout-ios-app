import XCTest
import CadenceCore
@testable import CadenceFeatures

final class TodaySuggestedWorkoutCacheTests: XCTestCase {
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

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi, second: s))!
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("today-cache-\(UUID().uuidString).json")
    }

    private static func payload(title: String = "Push") -> TodaySuggestedPlanPayload {
        TodaySuggestedPlanPayload(EditablePlan(
            title: title, warmupMinutes: 5, cooldownMinutes: 3,
            exercises: [EditableExercise(
                name: "Bench Press",
                sets: [EditableSet(targetReps: 8, targetWeight: 60,
                                   loadMode: .percentageOfOneRepMax, oneRepMaxPercent: 0.7)],
                notes: "")],
            enginePlanId: "plan", engineRevisionId: "rev", enginePlanJSON: Data([1, 2]),
            suggestedWorkoutStyle: .fitness,
            recommendationRationale: SuggestedWorkoutRationale(
                whyWorkout: "why",
                exercises: [SuggestedExerciseRationale(exerciseName: "Bench Press",
                                                       whyExercise: "a", whySetRep: "b")])))
    }

    private func input(goal: TrainingGoal = .strength, ids: [String] = ["a"]) -> SuggestedWorkoutInput {
        SuggestedWorkoutInput(
            completedSetsByMuscle: ["chest": 3],
            candidates: ids.map {
                SuggestedExerciseCandidate(id: $0, name: $0, mechanics: .compound,
                                           primaryMuscles: ["chest"], secondaryMuscles: [],
                                           equipment: nil, volumeEligible: true,
                                           trainingTypes: [], modalities: [], sportContexts: [],
                                           isPersonalized: false)
            },
            preferredSetsPerExercise: 3, trainingGoal: goal)
    }

    private func fp(_ i: SuggestedWorkoutInput, extras: [String] = []) -> String {
        TodaySuggestedWorkoutFingerprint.make(input: i, unitRaw: "kg", warmupMinutes: 5,
                                              cooldownMinutes: 3, extras: extras)
    }

    func testRestartHitInvokesGeneratorZeroTimes() async {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let now = date(2026, 3, 10, 9, 0, 0)
        let counter = Counter()
        let a = TodaySuggestedWorkoutCacheStore(fileURL: url, calendar: cal, now: { now })
        _ = await a.resolve(fingerprint: "f") { counter.bump(); return Self.payload() }
        let b = TodaySuggestedWorkoutCacheStore(fileURL: url, calendar: cal, now: { now })
        let hit = await b.resolve(fingerprint: "f") { counter.bump(); return Self.payload() }
        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(hit, Self.payload())
    }

    func testFingerprintIgnoresNothingButRealInputs() {
        XCTAssertEqual(fp(input()), fp(input()))
        XCTAssertNotEqual(fp(input()), fp(input(goal: .hypertrophy)))
        XCTAssertNotEqual(fp(input()), fp(input(ids: ["a", "b"])))
        XCTAssertNotEqual(fp(input()), fp(input(), extras: ["scheduled"]))
    }

    func testLocalDayBoundary() async {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let clock = Clock(date(2026, 3, 7, 0, 0, 0))
        let store = TodaySuggestedWorkoutCacheStore(fileURL: url, calendar: cal, now: { clock.date })
        await store.save(Self.payload(), fingerprint: "f")
        clock.date = date(2026, 3, 7, 23, 59, 59)
        var hit = await store.restore(fingerprint: "f")
        XCTAssertNotNil(hit)
        clock.date = date(2026, 3, 8, 0, 0, 0)  // DST spring-forward day
        hit = await store.restore(fingerprint: "f")
        XCTAssertNil(hit)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testInvalidateAndFingerprintChangeMiss() async {
        let store = TodaySuggestedWorkoutCacheStore(fileURL: nil, calendar: cal, now: { Date() })
        await store.save(Self.payload(), fingerprint: "f")
        var miss = await store.restore(fingerprint: "g")
        XCTAssertNil(miss)
        await store.save(Self.payload(), fingerprint: "f")
        await store.invalidate()
        miss = await store.restore(fingerprint: "f")
        XCTAssertNil(miss)
    }

    func testConcurrentResolvesCoalesce() async {
        let store = TodaySuggestedWorkoutCacheStore(fileURL: nil, calendar: cal, now: { Date() })
        let counter = Counter()
        let p = Self.payload()
        async let x = store.resolve(fingerprint: "f") {
            counter.bump(); try? await Task.sleep(nanoseconds: 100_000_000); return p
        }
        async let y = store.resolve(fingerprint: "f") { counter.bump(); return p }
        _ = await (x, y)
        XCTAssertEqual(counter.value, 1)
    }

    func testInvalidatedInFlightGenerationDoesNotWrite() async {
        let store = TodaySuggestedWorkoutCacheStore(fileURL: nil, calendar: cal, now: { Date() })
        let p = Self.payload()
        async let r = store.resolve(fingerprint: "old") {
            try? await Task.sleep(nanoseconds: 100_000_000); return p
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await store.invalidate()
        _ = await r
        let hit = await store.restore(fingerprint: "old")
        XCTAssertNil(hit)
    }

    func testPayloadRoundTripPreservesProvenanceAndRationale() throws {
        let data = try JSONEncoder().encode(Self.payload())
        let plan = try JSONDecoder().decode(TodaySuggestedPlanPayload.self, from: data).makePlan()
        XCTAssertEqual(plan.title, "Push")
        XCTAssertEqual(plan.enginePlanId, "plan")
        XCTAssertEqual(plan.enginePlanJSON, Data([1, 2]))
        XCTAssertEqual(plan.suggestedWorkoutStyle, .fitness)
        XCTAssertEqual(plan.recommendationRationale?.whyWorkout, "why")
        XCTAssertEqual(plan.exercises.first?.sets.first?.loadMode, .percentageOfOneRepMax)
    }

    func testCorruptAndWrongVersionRecover() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        try Data("garbage".utf8).write(to: url)
        let store = TodaySuggestedWorkoutCacheStore(fileURL: url, calendar: cal, now: { Date() })
        let miss = await store.restore(fingerprint: "f")
        XCTAssertNil(miss)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        let writer = TodaySuggestedWorkoutCacheStore(fileURL: url, calendar: cal, now: { Date() })
        await writer.save(Self.payload(), fingerprint: "f")
        var json = try String(contentsOf: url, encoding: .utf8)
        json = json.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":99")
        try json.write(to: url, atomically: true, encoding: .utf8)
        let reader = TodaySuggestedWorkoutCacheStore(fileURL: url, calendar: cal, now: { Date() })
        let old = await reader.restore(fingerprint: "f")
        XCTAssertNil(old)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
