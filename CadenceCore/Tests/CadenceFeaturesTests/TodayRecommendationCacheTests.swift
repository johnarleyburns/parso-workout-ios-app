import XCTest
import CadenceCore
@testable import CadenceFeatures

final class TodayRecommendationCacheTests: XCTestCase {
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
    private var fixed: Date { day(5) }
    private func url() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString).json")
    }
    private func payload(_ title: String = "Push Day") -> TodayRecommendationPayload {
        TodayRecommendationPayload(
            hero: TodayHero(kind: .suggested, title: title, estimatedMinutes: 45,
                            exercises: [.init(name: "Bench", detail: "3 × 8")],
                            reason: "why", citationIDs: ["c1"]),
            primaryIsStrength: true)
    }
    private func fp(dayKey: String = "d", sessions: String = "s", goal: TrainingGoal = .strength,
                    experience: ExperienceLevel = .intermediate, formula: OneRepMaxFormula = .epley,
                    schedule: CoachSchedulePreferences = CoachSchedulePreferences(),
                    profile: CoachPreferenceProfile = .empty, age: Int? = 30, hr: Double? = nil,
                    override: String? = nil, pain: Bool = false, readiness: String = "r",
                    samples: [PassiveReadinessSample] = []) -> TodayRecommendationFingerprint.Result {
        TodayRecommendationFingerprint.make(
            dayKey: dayKey, sessionsStamp: sessions, cardioStamp: "c", assessmentsStamp: "a",
            readinessStamp: readiness, painToday: pain, goal: goal, experience: experience,
            formula: formula, schedule: schedule, profile: profile, userAge: age,
            cardioMaximumHROverride: hr, overrideWeekKey: override, passiveSamples: samples)
    }

    func testRestartRestoresFromDisk() async {
        let fixed = self.fixed
        let u = url(); defer { try? FileManager.default.removeItem(at: u) }
        let clock = Clock(day(5))
        let a = TodayRecommendationCacheStore(fileURL: u, calendar: cal, now: { clock.date })
        let f = fp()
        await a.save(payload(), fingerprint: f.fingerprint, passiveStamp: f.passiveStamp)
        // New store instance == new process reading the same Application Support file.
        let b = TodayRecommendationCacheStore(fileURL: u, calendar: cal, now: { clock.date })
        let hit = await b.restore(fingerprint: f.fingerprint, passiveStamp: nil)
        XCTAssertEqual(hit?.payload, payload())
        XCTAssertEqual(hit?.payload.makeHero().title, "Push Day")
        let again = await b.restore(fingerprint: f.fingerprint, passiveStamp: f.passiveStamp)
        XCTAssertNotNil(again)
    }

    func testNewLocalDayDiscards() async {
        let fixed = self.fixed
        let u = url(); defer { try? FileManager.default.removeItem(at: u) }
        let clock = Clock(day(5))
        let s = TodayRecommendationCacheStore(fileURL: u, calendar: cal, now: { clock.date })
        await s.save(payload(), fingerprint: "f", passiveStamp: "p")
        clock.date = day(6)
        let hit = await s.restore(fingerprint: "f")
        XCTAssertNil(hit)
        XCTAssertFalse(FileManager.default.fileExists(atPath: u.path))
    }

    func testWrongFingerprintAndPassiveMismatchDiscard() async {
        let fixed = self.fixed
        let u = url(); defer { try? FileManager.default.removeItem(at: u) }
        let s = TodayRecommendationCacheStore(fileURL: u, calendar: cal, now: { fixed })
        await s.save(payload(), fingerprint: "f", passiveStamp: "p")
        let wrong = await s.restore(fingerprint: "other")
        XCTAssertNil(wrong)
        await s.save(payload(), fingerprint: "f", passiveStamp: "p")
        let passive = await s.restore(fingerprint: "f", passiveStamp: "q")
        XCTAssertNil(passive)
    }

    func testCorruptAndOldSchemaDiscarded() async throws {
        let fixed = self.fixed
        let u = url(); defer { try? FileManager.default.removeItem(at: u) }
        try Data("not json".utf8).write(to: u)
        let s = TodayRecommendationCacheStore(fileURL: u, calendar: cal, now: { fixed })
        let corrupt = await s.restore(fingerprint: "f")
        XCTAssertNil(corrupt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: u.path))

        let writer = TodayRecommendationCacheStore(fileURL: u, calendar: cal, now: { fixed })
        await writer.save(payload(), fingerprint: "f", passiveStamp: "p")
        var json = try String(contentsOf: u, encoding: .utf8)
        json = json.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":0")
        try json.write(to: u, atomically: true, encoding: .utf8)
        let old = TodayRecommendationCacheStore(fileURL: u, calendar: cal, now: { fixed })
        let oldHit = await old.restore(fingerprint: "f")
        XCTAssertNil(oldHit)
    }

    func testInvalidateRemovesDurableEntry() async {
        let fixed = self.fixed
        let u = url(); defer { try? FileManager.default.removeItem(at: u) }
        let s = TodayRecommendationCacheStore(fileURL: u, calendar: cal, now: { fixed })
        await s.save(payload(), fingerprint: "f", passiveStamp: "p")
        await s.invalidate()
        let hit = await TodayRecommendationCacheStore(fileURL: u, calendar: cal, now: { fixed })
            .restore(fingerprint: "f")
        XCTAssertNil(hit)
    }

    func testFingerprintDeterministicAndSensitive() {
        XCTAssertEqual(fp(), fp())
        let base = fp().fingerprint
        var seen: Set<String> = [base]
        var other = CoachSchedulePreferences(); other.allowsTwoADays.toggle()
        let variants = [
            fp(dayKey: "d2"), fp(sessions: "s2"), fp(goal: .hypertrophy), fp(experience: .advanced),
            fp(formula: .brzycki), fp(schedule: other), fp(age: 31), fp(hr: 190),
            fp(override: "2026-W10"), fp(pain: true), fp(readiness: "r2")
        ]
        for v in variants { XCTAssertTrue(seen.insert(v.fingerprint).inserted) }
    }

    func testPassiveSamplesOnlyChangePassiveStamp() {
        let s = [PassiveReadinessSample(date: day(5), hrvSDNN: 50, restingHR: 55, sleepHours: 7)]
        XCTAssertEqual(fp().fingerprint, fp(samples: s).fingerprint)
        XCTAssertNotEqual(fp().passiveStamp, fp(samples: s).passiveStamp)
    }

    func testSuggestedPlanStoreReportsSameDayEntryForDelaySkip() async {
        let fixed = self.fixed
        let u = url(); defer { try? FileManager.default.removeItem(at: u) }
        let clock = Clock(day(5))
        let s = TodaySuggestedWorkoutCacheStore(fileURL: u, calendar: cal, now: { clock.date })
        let none = await s.hasSameDayEntry()
        XCTAssertFalse(none)
        let plan = TodaySuggestedPlanPayload(EditablePlan(
            title: "P", warmupMinutes: 0, cooldownMinutes: 0,
            exercises: [EditableExercise(name: "Squat", sets: [EditableSet(targetReps: 5, targetWeight: nil)], notes: "")]))
        await s.save(plan, fingerprint: "f")
        let has = await s.hasSameDayEntry()
        XCTAssertTrue(has)
        clock.date = day(6)
        let next = await s.hasSameDayEntry()
        XCTAssertFalse(next)
    }
}
