import XCTest
import SwiftData
@testable import CadenceCore

/// Fix 6 (planned strength days expose a concrete exercise list) + Fix 7 (a
/// high-frequency lifter gets a split week with ~their real number of strength
/// days on distinct-focus consecutive days). Pure `WeeklyPlan` logic.
final class WeeklyPlanSplitTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    /// Fixed absolute Thursday (2026-06-25 12:00) — deterministic weekly windows.
    private var testNow: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 25
        comps.hour = 12; comps.minute = 0; comps.second = 0
        return Calendar.current.date(from: comps) ?? Date(timeIntervalSince1970: 1_750_000_000)
    }

    private func makeStrengthEvent(context: ModelContext, name: String,
                                   primaryMuscles: [String], date: Date,
                                   sets: Int = 3, rpe: Double? = 8) throws -> TrainingEvent {
        let session = try WorkoutRepository.createSession(date: date.addingTimeInterval(-600), in: context)
        let ex = try WorkoutRepository.findOrCreateExercise(
            named: name, primaryMuscles: primaryMuscles, in: context)
        for _ in 0..<sets {
            _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 100, reps: 5,
                                             rpe: rpe, completedAt: date, in: context)
        }
        session.endedAt = date
        return TrainingEvent.from(session: session)!
    }

    // MARK: - Fix 6: concrete exercises on planned strength days

    func testPlannedStrengthDayExposesConcreteExercises() throws {
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .hypertrophy, experience: .intermediate, now: now)
        let plan = WeeklyPlan.generate(from: facts)

        let strengthDays = plan.nextWeekDays.flatMap(\.sessions).filter { $0.kind == .strength }
        XCTAssertFalse(strengthDays.isEmpty, "next week should plan at least one strength day")
        let withExercises = strengthDays.first { !($0.exercises ?? []).isEmpty }
        let exercises = try XCTUnwrap(withExercises?.exercises,
                                      "a planned strength day must carry a concrete exercise list")
        XCTAssertFalse(exercises.isEmpty)
        for ex in exercises {
            XCTAssertFalse(ex.name.isEmpty)
            XCTAssertGreaterThanOrEqual(ex.sets ?? 0, 1, "each exercise should have >= 1 set")
            XCTAssertNotNil(ex.repLadder, "each exercise should carry a rep ladder")
        }
    }

    // MARK: - Fix 7: infer frequency from history + split rotation

    func testFiveDayHistoryYieldsAboutFivePlannedStrengthDaysWithSplitFocuses() throws {
        let ctx = try makeContext()
        let now = testNow
        // 5 strength days in the trailing week, despite the stored preference of 2.
        var events: [TrainingEvent] = []
        let lifts = ["Bench Press", "Back Squat", "Overhead Press", "Romanian Deadlift", "Barbell Row"]
        let muscles = [["chest"], ["quadriceps"], ["delts"], ["hamstrings", "glutes"], ["lats"]]
        for i in 0..<5 {
            events.append(try makeStrengthEvent(context: ctx, name: lifts[i],
                                                 primaryMuscles: muscles[i],
                                                 date: now.addingTimeInterval(Double(-(i + 1)) * 86400)))
        }
        let facts = CoachFacts.make(from: events, goal: .hypertrophy, experience: .intermediate, now: now)
        let prefs = CoachSchedulePreferences(strengthDaysPerWeek: 2, cardioDaysPerWeek: 3)

        let plan = WeeklyPlan.generate(from: facts, schedulePreferences: prefs)
        let nextWeekStrengthDays = plan.nextWeekDays.filter { day in
            day.sessions.contains { $0.kind == .strength }
        }
        // Inferred floor (5) should raise the plan well above the stored preference (2).
        XCTAssertGreaterThanOrEqual(nextWeekStrengthDays.count, 4,
            "a 5×/week lifter should get ~5 planned strength days, got \(nextWeekStrengthDays.count)")

        // Split focuses should differ across consecutive strength days.
        let focuses = nextWeekStrengthDays
            .sorted { $0.date < $1.date }
            .compactMap { d in d.sessions.first { $0.kind == .strength }?.focus }
        XCTAssertTrue(focuses.contains(.upper) && focuses.contains(.lower),
                      "a split week should rotate upper/lower focuses, got \(focuses)")
        // No two consecutive strength days share the same focus.
        for i in 1..<focuses.count {
            XCTAssertNotEqual(focuses[i], focuses[i - 1],
                              "consecutive strength days must train different focuses")
        }
    }

    func testConsecutiveSplitStrengthDaysTrainDifferentExercises() throws {
        let ctx = try makeContext()
        let now = testNow
        var events: [TrainingEvent] = []
        for i in 0..<5 {
            events.append(try makeStrengthEvent(context: ctx, name: "Lift\(i)",
                                                 primaryMuscles: ["quadriceps"],
                                                 date: now.addingTimeInterval(Double(-(i + 1)) * 86400)))
        }
        let facts = CoachFacts.make(from: events, goal: .hypertrophy, experience: .intermediate, now: now)
        let plan = WeeklyPlan.generate(from: facts)

        let strengthSessions = plan.nextWeekDays
            .sorted { $0.date < $1.date }
            .compactMap { d in d.sessions.first { $0.kind == .strength } }
        // Upper and lower days should expose different exercise sets.
        let upper = strengthSessions.first { $0.focus == .upper }?.exercises?.map(\.name) ?? []
        let lower = strengthSessions.first { $0.focus == .lower }?.exercises?.map(\.name) ?? []
        XCTAssertFalse(upper.isEmpty, "upper day should have exercises")
        XCTAssertFalse(lower.isEmpty, "lower day should have exercises")
        XCTAssertNotEqual(Set(upper), Set(lower),
                          "upper and lower split days must differ in movements")
    }

    func testLowFrequencyHistoryStaysWholeBodyNoSplit() throws {
        let ctx = try makeContext()
        let now = testNow
        // Only 2 strength days in the trailing week → whole-body, no split.
        let events = [
            try makeStrengthEvent(context: ctx, name: "Bench Press", primaryMuscles: ["chest"],
                                  date: now.addingTimeInterval(-2 * 86400)),
            try makeStrengthEvent(context: ctx, name: "Back Squat", primaryMuscles: ["quadriceps"],
                                  date: now.addingTimeInterval(-5 * 86400)),
        ]
        let facts = CoachFacts.make(from: events, goal: .strength, experience: .intermediate, now: now)
        let prefs = CoachSchedulePreferences(strengthDaysPerWeek: 2, cardioDaysPerWeek: 3)
        let plan = WeeklyPlan.generate(from: facts, schedulePreferences: prefs)

        let strengthSessions = plan.nextWeekDays.flatMap(\.sessions).filter { $0.kind == .strength }
        XCTAssertFalse(strengthSessions.isEmpty)
        // Whole-body plans should not carry upper/lower split focuses.
        XCTAssertTrue(strengthSessions.allSatisfy { $0.focus == nil || $0.focus == .fullBody },
                      "low-frequency plans should stay whole-body (no split focus)")
    }

    func testWholeBodyModeStillBlocksConsecutiveStrengthDays() throws {
        let now = testNow
        // Empty history, default prefs → whole-body low-frequency plan.
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let prefs = CoachSchedulePreferences(strengthDaysPerWeek: 3, cardioDaysPerWeek: 3)
        let plan = WeeklyPlan.generate(from: facts, schedulePreferences: prefs)

        let strengthDates = plan.nextWeekDays
            .filter { $0.sessions.contains { $0.kind == .strength } }
            .map { Calendar.current.startOfDay(for: $0.date) }
            .sorted()
        // No two whole-body strength days should be back-to-back.
        for i in 1..<max(1, strengthDates.count) {
            let gap = Calendar.current.dateComponents([.day],
                        from: strengthDates[i - 1], to: strengthDates[i]).day ?? 0
            XCTAssertGreaterThanOrEqual(gap, 2,
                "whole-body strength days must not be consecutive, gap was \(gap)")
        }
    }

    // MARK: - Fix 7: frequency/split copy resolves its citations (HARD RULE)

    func testSplitScienceCitationsAllResolve() throws {
        // The planned-day preview cites these IDs for a split strength day; every
        // one must resolve in the registry (no raw/broken IDs shown to the user).
        for id in ["schoenfeld2021", "frequencyMeta", "ramosCampoSplit2024", "parejaBlancoRecovery2020"] {
            XCTAssertNotNil(CitationRegistry.citation(forId: id),
                            "split-week citation id \(id) must resolve")
        }
    }
}
