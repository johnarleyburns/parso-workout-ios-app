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

final class TodaySuggestionCacheOutcomeTests: XCTestCase {
    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [TodaySuggestionCacheOutcome] = []
        var all: [TodaySuggestionCacheOutcome] { lock.lock(); defer { lock.unlock() }; return items }
        func add(_ o: TodaySuggestionCacheOutcome) { lock.lock(); items.append(o); lock.unlock() }
    }
    private final class Clock: @unchecked Sendable {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("sugg-\(UUID().uuidString).json")
    }
    private static func payload() -> TodaySuggestedPlanPayload {
        TodaySuggestedPlanPayload(EditablePlan(
            title: "Secret Title", warmupMinutes: 5, cooldownMinutes: 3,
            exercises: [EditableExercise(name: "Secret Lift",
                                         sets: [EditableSet(targetReps: 5, targetWeight: 50)], notes: "")]))
    }
    private func store(_ url: URL?, _ clock: Clock = Clock(), sink: Sink? = nil) -> TodaySuggestedWorkoutCacheStore {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let observer: (@Sendable (TodaySuggestionCacheOutcome) -> Void)? = sink.map { sink in
            { @Sendable (o: TodaySuggestionCacheOutcome) in sink.add(o) }
        }
        let cal2 = cal
        return TodaySuggestedWorkoutCacheStore(fileURL: url, calendar: cal2, now: { clock.date },
                                               outcomeObserver: observer)
    }
    /// A directory path used as the file target: writes (and replacement) fail.
    private func unwritable() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("missing/sub/file.json")
    }

    func testFreshProcessRestoresValidFile() async {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let clock = Clock()
        let w = await store(url, clock).resolveWithOutcome(fingerprint: "f", earlyKey: "k") { Self.payload() }
        XCTAssertEqual(w.outcome, .writeSaved); XCTAssertTrue(w.persisted)
        let peek = await store(url, clock).inspectDisplayable()
        XCTAssertEqual(peek.resolution.outcome, .displayRestored)
        XCTAssertTrue(peek.resolution.persisted)
        let early = await store(url, clock).restoreEarlyResolution(earlyKey: "k")
        XCTAssertEqual(early.outcome, .earlyKeyMatch); XCTAssertTrue(early.persisted)
    }

    func testDistinctMissOutcomes() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let clock = Clock()
        let none = await store(url, clock).restoreEarlyResolution(earlyKey: "k")
        XCTAssertEqual(none.outcome, .noFile)

        try Data("garbage".utf8).write(to: url)
        let corrupt = await store(url, clock).restoreEarlyResolution(earlyKey: "k")
        XCTAssertEqual(corrupt.outcome, .corrupt)

        await store(url, clock).save(Self.payload(), fingerprint: "f", earlyKey: "k")
        let json = try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":99")
        try json.write(to: url, atomically: true, encoding: .utf8)
        let schema = await store(url, clock).restoreEarlyResolution(earlyKey: "k")
        XCTAssertEqual(schema.outcome, .schemaRejected)

        await store(url, clock).save(Self.payload(), fingerprint: "f", earlyKey: "k")
        let tomorrow = Clock(); tomorrow.date = clock.date.addingTimeInterval(86_400 * 2)
        let day = await store(url, tomorrow).restoreEarlyResolution(earlyKey: "k")
        XCTAssertEqual(day.outcome, .dayRejected)

        await store(url, clock).save(Self.payload(), fingerprint: "f", earlyKey: "k")
        let early = await store(url, clock).restoreEarlyResolution(earlyKey: "other")
        XCTAssertEqual(early.outcome, .earlyKeyRejected)

        await store(url, clock).save(Self.payload(), fingerprint: "f", earlyKey: "k")
        let s = store(url, clock)
        let full = await s.resolveWithOutcome(fingerprint: "g") { nil }
        XCTAssertEqual(full.outcome, .fullKeyRejected); XCTAssertNil(full.payload)
    }

    func testWriteFailureKeepsPreviousValidFile() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let clock = Clock()
        await store(url, clock).save(Self.payload(), fingerprint: "f", earlyKey: "k")
        let before = try Data(contentsOf: url)
        // Replacement target becomes a directory so the atomic write cannot land.
        let bad = try unwritable()
        let failing = store(bad, clock)
        let r = await failing.resolveWithOutcome(fingerprint: "f") { Self.payload() }
        XCTAssertEqual(r.outcome, .writeFailed)
        XCTAssertFalse(r.persisted)
        XCTAssertNotNil(r.payload)
        XCTAssertEqual(try Data(contentsOf: url), before)
        let fresh = await store(url, clock).restoreEarlyResolution(earlyKey: "k")
        XCTAssertEqual(fresh.outcome, .earlyKeyMatch)
    }

    func testUnavailableStorageNeverClaimsPersistence() async {
        let s = store(nil)
        let r = await s.resolveWithOutcome(fingerprint: "f") { Self.payload() }
        XCTAssertEqual(r.outcome, .storageUnavailable)
        XCTAssertFalse(r.persisted)
        XCTAssertNotNil(r.payload)
        let again = await s.inspectDisplayable()
        XCTAssertFalse(again.resolution.persisted)
        let empty = await store(nil).inspectDisplayable()
        XCTAssertEqual(empty.resolution.outcome, .storageUnavailable)
    }

    func testInvalidatedDuringGenerationDoesNotWriteOrCorruptValidSave() async throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let s = store(url)
        let p = Self.payload()
        async let r = s.resolveWithOutcome(fingerprint: "old") {
            try? await Task.sleep(nanoseconds: 100_000_000); return p
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        await s.invalidate()
        await s.save(p, fingerprint: "new", earlyKey: "k")
        let res = await r
        XCTAssertEqual(res.outcome, .invalidated); XCTAssertFalse(res.persisted)
        let hit = await store(url).restoreEarlyResolution(earlyKey: "k")
        XCTAssertEqual(hit.outcome, .earlyKeyMatch)
    }

    func testObserverReceivesOutcomeNamesOnly() async {
        let sink = Sink()
        let s = store(nil, sink: sink)
        _ = await s.resolveWithOutcome(fingerprint: "f") { Self.payload() }
        let names = sink.all.map(\.rawValue)
        XCTAssertEqual(names, ["storageUnavailable"])
        XCTAssertFalse(names.joined().contains("Secret"))
    }
}
