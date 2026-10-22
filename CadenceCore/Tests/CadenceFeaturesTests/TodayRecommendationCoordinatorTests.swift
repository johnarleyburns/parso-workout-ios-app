import XCTest
import CadenceCore
@testable import CadenceFeatures

/// Production-boundary tests: the same coordinator `HomeTodayCache` uses, driven
/// the way `HomeView.runCoachTask` drives it (restore → compute → store).
@MainActor
final class TodayRecommendationCoordinatorTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    private var urls: [URL] = []

    override func tearDown() {
        urls.forEach { try? FileManager.default.removeItem(at: $0) }
        urls = []
    }

    private func url() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("c-\(UUID().uuidString).json")
        urls.append(u); return u
    }
    private func make(rec: URL, plan: URL, now: @escaping @Sendable () -> Date = { Date() })
        -> TodayRecommendationCoordinator<String> {
        TodayRecommendationCoordinator(
            recommendationStore: TodayRecommendationCacheStore(fileURL: rec, calendar: cal, now: now),
            suggestionStore: TodaySuggestedWorkoutCacheStore(fileURL: plan, calendar: cal, now: now))
    }
    private func payload(_ t: String) -> TodayRecommendationPayload {
        TodayRecommendationPayload(
            hero: TodayHero(kind: .suggested, title: t, estimatedMinutes: 30,
                            exercises: [.init(name: "Squat", detail: "5x5")], reason: nil, citationIDs: []),
            primaryIsStrength: true)
    }
    private func fp(day: String = "d", sessions: String = "s", goal: TrainingGoal = .strength,
                    experience: ExperienceLevel = .intermediate, readiness: String = "r",
                    pain: Bool = false, age: Int? = 30, hr: Double? = nil, override: String? = nil,
                    schedule: CoachSchedulePreferences = CoachSchedulePreferences(),
                    samples: [PassiveReadinessSample] = []) -> TodayRecommendationFingerprint.Result {
        TodayRecommendationFingerprint.make(
            dayKey: day, sessionsStamp: sessions, cardioStamp: "c", assessmentsStamp: "a",
            readinessStamp: readiness, painToday: pain, goal: goal, experience: experience,
            formula: .epley, schedule: schedule, profile: .empty, userAge: age,
            cardioMaximumHROverride: hr, overrideWeekKey: override, passiveSamples: samples)
    }

    /// Mirrors `HomeView.runCoachTask`: returns the title shown and whether the pipeline ran.
    private func runLifecycle(_ c: TodayRecommendationCoordinator<String>, surface: TodayCacheSurface,
                              key: TodayRecommendationFingerprint.Result, computed: inout Int,
                              title: String) async -> (shown: String, loading: Bool) {
        await c.settle()
        if let hit = c.cachedSnapshot(fingerprint: key.fingerprint, passiveStamp: key.passiveStamp) {
            return (hit, false)
        }
        let durable = await c.restoreDurable(fingerprint: key.fingerprint, passiveStamp: key.passiveStamp,
                                             surface: surface)
        if let durable { return (durable.payload.title, false) }
        computed += 1
        c.store(title, payload: payload(title), fingerprint: key.fingerprint,
                passiveStamp: key.passiveStamp, surface: surface)
        return (title, true)
    }

    func testTodayThisWeekTodayRestoresWithoutRecompute() async {
        let rec = url(), plan = url()
        let c = make(rec: rec, plan: plan)
        let key = fp(); var n = 0
        _ = await runLifecycle(c, surface: .today, key: key, computed: &n, title: "Today A")
        await c.settle()
        let before = try? Data(contentsOf: rec)
        XCTAssertNotNil(before)
        // This Week computes its own snapshot (a different result) on the same inputs.
        XCTAssertFalse(c.store("Week", payload: payload("Week"), fingerprint: key.fingerprint,
                               passiveStamp: key.passiveStamp, surface: .thisWeek))
        c.invalidate(surface: .thisWeek)
        let none = await c.restoreDurable(fingerprint: "other", passiveStamp: nil, surface: .thisWeek)
        XCTAssertNil(none)
        await c.settle()
        XCTAssertEqual(try? Data(contentsOf: rec), before)
        XCTAssertEqual(c.cachedSnapshot(fingerprint: key.fingerprint, passiveStamp: nil), "Today A")
        let back = await runLifecycle(c, surface: .today, key: key, computed: &n, title: "Today B")
        XCTAssertEqual(back.shown, "Today A"); XCTAssertFalse(back.loading); XCTAssertEqual(n, 1)
    }

    func testRecreatedViewAndRestartRestoreFromDurable() async {
        let rec = url(), plan = url()
        let c1 = make(rec: rec, plan: plan)
        let key = fp(); var n = 0
        _ = await runLifecycle(c1, surface: .today, key: key, computed: &n, title: "Persisted")
        await c1.settle()
        let c2 = make(rec: rec, plan: plan)   // fresh process, same Application Support file
        let r = await runLifecycle(c2, surface: .today, key: key, computed: &n, title: "Recomputed")
        XCTAssertEqual(r.shown, "Persisted"); XCTAssertFalse(r.loading); XCTAssertEqual(n, 1)
    }

    func testInvalidationBoundariesRecompute() async {
        let t = Date()
        let cases: [(String, TodayRecommendationFingerprint.Result)] = [
            ("day", fp(day: "d2")), ("history", fp(sessions: "s2")),
            ("goal", fp(goal: .hypertrophy)), ("experience", fp(experience: .advanced)),
            ("readiness", fp(readiness: "r2")), ("pain", fp(pain: true)), ("age", fp(age: 31)),
            ("hr", fp(hr: 190)), ("override", fp(override: "2026-W10")),
            ("schedule", fp(schedule: { var x = CoachSchedulePreferences(); x.dailyStepTarget = 12_345; return x }())),
            ("passive", fp(samples: [PassiveReadinessSample(date: t, hrvSDNN: 40, restingHR: 55, sleepHours: 7)]))
        ]
        for (name, changed) in cases {
            let c = make(rec: url(), plan: url())
            var n = 0
            _ = await runLifecycle(c, surface: .today, key: fp(), computed: &n, title: "old")
            _ = await runLifecycle(c, surface: .today, key: changed, computed: &n, title: "new")
            XCTAssertEqual(n, 2, "\(name) must recompute")
        }
    }

    func testStaleDayCorruptAndOldSchemaFallBackToOneRecompute() async {
        final class Clock: @unchecked Sendable { var d: Date; init(_ d: Date) { self.d = d } }
        let clock = Clock(cal.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 9))!)
        let rec = url(), plan = url()
        let c1 = make(rec: rec, plan: plan, now: { clock.d })
        let key = fp(); var n = 0
        _ = await runLifecycle(c1, surface: .today, key: key, computed: &n, title: "x")
        await c1.settle()
        clock.d = clock.d.addingTimeInterval(86_400)
        let c2 = make(rec: rec, plan: plan, now: { clock.d })
        _ = await runLifecycle(c2, surface: .today, key: key, computed: &n, title: "y")
        XCTAssertEqual(n, 2)
        try? Data("{not json".utf8).write(to: rec)
        let c3 = make(rec: rec, plan: plan, now: { clock.d })
        _ = await runLifecycle(c3, surface: .today, key: key, computed: &n, title: "z")
        XCTAssertEqual(n, 3)
        await c3.settle()
        let old = String(decoding: (try? Data(contentsOf: rec)) ?? Data(), as: UTF8.self)
            .replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":0")
        try? Data(old.utf8).write(to: rec)
        let c4 = make(rec: rec, plan: plan, now: { clock.d })
        _ = await runLifecycle(c4, surface: .today, key: key, computed: &n, title: "w")
        XCTAssertEqual(n, 4)
    }

    func testQueuedSaveCannotRepopulateAfterInvalidation() async {
        let rec = url()
        let c = make(rec: rec, plan: url())
        let key = fp()
        c.store("v", payload: payload("v"), fingerprint: key.fingerprint,
                passiveStamp: key.passiveStamp, surface: .today)
        c.invalidate(surface: .today)   // before the queued save ran
        await c.settle()
        XCTAssertFalse(FileManager.default.fileExists(atPath: rec.path))
        let hit = await c.restoreDurable(fingerprint: key.fingerprint, passiveStamp: nil, surface: .today)
        XCTAssertNil(hit)
    }

    func testValidPlanRestoreSkipsColdGenerationDelay() async {
        let c = make(rec: url(), plan: url())
        let cold = await c.suggestionStore.hasSameDayEntry()
        XCTAssertFalse(cold)
        let plan = TodaySuggestedPlanPayload(EditablePlan(
            title: "Push", warmupMinutes: 5, cooldownMinutes: 3,
            exercises: [EditableExercise(
                name: "Bench Press",
                sets: [EditableSet(targetReps: 8, targetWeight: 60,
                                   loadMode: .percentageOfOneRepMax, oneRepMaxPercent: 0.7)],
                notes: "")],
            enginePlanId: "plan", engineRevisionId: "rev", enginePlanJSON: Data([1]),
            suggestedWorkoutStyle: .fitness, recommendationRationale: nil))
        await c.suggestionStore.save(plan, fingerprint: "f")
        let warm = await c.suggestionStore.hasSameDayEntry()
        XCTAssertTrue(warm)
    }

    // MARK: Provisional cold-launch restore (mirrors HomeView.runCoachTask)

    private func seed(_ c: TodayRecommendationCoordinator<String>, key: TodayRecommendationFingerprint.Result) async {
        c.store("A", payload: payload("A"), fingerprint: key.fingerprint,
                passiveStamp: key.passiveStamp, surface: .today)
        await c.settle()
    }

    func testPartialStartupInputsShowCachedImmediatelyWithoutDeleteOrRecompute() async {
        let rec = url(), plan = url()
        let key = fp(sessions: "full")
        await seed(make(rec: rec, plan: plan), key: key)
        // New process: fresh coordinator, same files.
        let c = make(rec: rec, plan: plan)
        var outcomes: [TodayCacheOutcome] = []
        c.outcomeObserver = { outcomes.append($0) }
        let hit = await c.restoreProvisional(surface: .today)
        XCTAssertEqual(hit?.payload.title, "A")            // rendered, no Loading
        XCTAssertTrue(FileManager.default.fileExists(atPath: rec.path))
        // Provisional (partial) inputs are never compared; settled inputs match.
        XCTAssertTrue(c.reconcileProvisional(stableFingerprint: key.fingerprint,
                                             stablePassiveStamp: key.passiveStamp, surface: .today))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rec.path))
        XCTAssertEqual(outcomes, [.provisionalRestore, .stableMatch])
    }

    func testSettledDifferentInputsInvalidateThenReplaceOnce() async {
        let rec = url(), plan = url()
        await seed(make(rec: rec, plan: plan), key: fp(sessions: "old"))
        let c = make(rec: rec, plan: plan)
        let hit = await c.restoreProvisional(surface: .today)
        XCTAssertEqual(hit?.payload.title, "A")
        let stable = fp(sessions: "new")
        XCTAssertFalse(c.reconcileProvisional(stableFingerprint: stable.fingerprint,
                                              stablePassiveStamp: stable.passiveStamp, surface: .today))
        XCTAssertEqual(c.lastOutcome, .stableInvalidation)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rec.path))  // not deleted on mismatch
        c.store("B", payload: payload("B"), fingerprint: stable.fingerprint,
                passiveStamp: stable.passiveStamp, surface: .today)
        await c.settle()
        let again = await make(rec: rec, plan: plan).restoreProvisional(surface: .today)
        XCTAssertEqual(again?.payload.title, "B")
    }

    func testUnusableRecordsFallBackToLoading() async {
        // wrong day
        let rec = url(), plan = url()
        let day1 = Date(timeIntervalSince1970: 1_800_000_000)
        await seed(make(rec: rec, plan: plan, now: { day1 }), key: fp())
        let nextDay = make(rec: rec, plan: plan, now: { day1.addingTimeInterval(86_400) })
        let none = await nextDay.restoreProvisional(surface: .today)
        XCTAssertNil(none); XCTAssertEqual(nextDay.lastOutcome, .dayRejected)
        // corrupt
        let bad = url()
        try? Data("not json".utf8).write(to: bad)
        let c = make(rec: bad, plan: plan)
        let corrupt = await c.restoreProvisional(surface: .today)
        XCTAssertNil(corrupt); XCTAssertEqual(c.lastOutcome, .corrupt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bad.path))
        // old schema
        let old = url()
        let json = """
        {"schemaVersion":0,"dayKey":"x","fingerprint":"f","passiveStamp":"p","updatedAt":0,
         "payload":{"isRest":false,"primaryIsStrength":true,"title":"t","exercises":[],"citationIDs":[]}}
        """
        try? Data(json.utf8).write(to: old)
        let c2 = make(rec: old, plan: plan)
        let schema = await c2.restoreProvisional(surface: .today)
        XCTAssertNil(schema); XCTAssertEqual(c2.lastOutcome, .schemaRejected)
        // no file
        let c3 = make(rec: url(), plan: plan)
        _ = await c3.restoreProvisional(surface: .today)
        XCTAssertEqual(c3.lastOutcome, .noFile)
    }

    func testThisWeekCannotProvisionallyRestoreOrReconcile() async {
        let rec = url(), plan = url()
        let key = fp()
        await seed(make(rec: rec, plan: plan), key: key)
        let c = make(rec: rec, plan: plan)
        let none = await c.restoreProvisional(surface: .thisWeek)
        XCTAssertNil(none)
        XCTAssertFalse(c.reconcileProvisional(stableFingerprint: key.fingerprint,
                                              stablePassiveStamp: key.passiveStamp, surface: .thisWeek))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rec.path))
    }
}
