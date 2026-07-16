import XCTest
import SwiftData
@testable import CadenceCore

/// Coach-user-control Phase 3 — the weekly planner honors the user's stated
/// targets. With the 2026-07-14 export's preferences (5 strength + 6 cardio
/// days/week, two-a-days, fixed Sunday rest) the generated week must contain
/// exactly what was asked for: recovery is advice, never a silent day-drop.
final class WeeklyPlanTargetsTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    /// Fixed Wednesday 2026-07-15 12:00 — deterministic weekly windows.
    private var testNow: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 15
        comps.hour = 12; comps.minute = 0; comps.second = 0
        return Calendar.current.date(from: comps) ?? Date(timeIntervalSince1970: 1_784_000_000)
    }

    private var exportPrefs: CoachSchedulePreferences {
        CoachSchedulePreferences(
            strengthDaysPerWeek: 5,
            cardioDaysPerWeek: 6,
            restPreference: .fixed(days: [.sunday]),
            allowsTwoADays: true,
            sameDayCardioTiming: .separateLater)
    }

    private func makeStrengthEvent(context: ModelContext, name: String,
                                   primaryMuscles: [String], date: Date,
                                   sets: Int = 6, rpe: Double? = 9) throws -> TrainingEvent {
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

    private func isSunday(_ date: Date) -> Bool {
        Calendar.current.component(.weekday, from: date) == 1
    }

    private func isCardio(_ s: PlannedSession) -> Bool {
        s.kind == .easyAerobic || s.kind == .moderateAerobic || s.kind == .vo2Intervals
    }

    /// The headline regression: 5 strength + 6 cardio days next week, Sunday is
    /// the only rest day, and no forced Recovery day anywhere.
    func testExportPrefsWeekContainsExactlyTheRequestedDays() throws {
        let facts = CoachFacts.make(from: [], goal: .hypertrophy,
                                    experience: .intermediate, now: testNow)
        let plan = WeeklyPlan.generate(from: facts, schedulePreferences: exportPrefs)
        let nextWeek = plan.nextWeekDays

        let strengthDays = nextWeek.filter { $0.sessions.contains { $0.kind == .strength } }
        let cardioDays = nextWeek.filter { $0.sessions.contains(where: isCardio) }
        XCTAssertEqual(strengthDays.count, 5,
                       "User asked for 5 strength days, got \(strengthDays.count)")
        XCTAssertEqual(cardioDays.count, 6,
                       "User asked for 6 cardio days, got \(cardioDays.count)")

        // Sunday is the only rest day; no day is silently converted to Recovery.
        for day in nextWeek {
            if isSunday(day.date) {
                XCTAssertTrue(day.sessions.allSatisfy { $0.kind == .rest },
                              "Fixed Sunday rest must hold")
            } else {
                XCTAssertFalse(day.sessions.contains { $0.kind == .rest || $0.kind == .recovery },
                               "\(day.date): a scheduled training day must not become rest/recovery")
            }
        }
        XCTAssertFalse(plan.futureDays.flatMap(\.sessions).contains { $0.kind == .recovery },
                       "The planner never forces a Recovery day")
    }

    /// Two-a-days: every non-rest day carries cardio, and the 5 strength days
    /// pair strength AND cardio on the same day.
    func testTwoADaysPairBothModalitiesOnNonRestDays() throws {
        let facts = CoachFacts.make(from: [], goal: .hypertrophy,
                                    experience: .intermediate, now: testNow)
        let plan = WeeklyPlan.generate(from: facts, schedulePreferences: exportPrefs)

        for day in plan.nextWeekDays where !isSunday(day.date) {
            XCTAssertTrue(day.sessions.contains(where: isCardio),
                          "\(day.date): every non-rest day should carry a cardio session")
        }
        let twoADayCount = plan.nextWeekDays.filter { day in
            day.sessions.contains { $0.kind == .strength } && day.sessions.contains(where: isCardio)
        }.count
        XCTAssertEqual(twoADayCount, 5, "All 5 strength days should pair with cardio")
    }

    /// Planned cardio carries a real prescription (duration + target zone).
    func testPlannedCardioCarriesPrescription() throws {
        let facts = CoachFacts.make(from: [], goal: .hypertrophy,
                                    experience: .intermediate, now: testNow)
        let plan = WeeklyPlan.generate(from: facts, schedulePreferences: exportPrefs)
        let cardio = plan.nextWeekDays.flatMap(\.sessions).filter(isCardio)
        XCTAssertFalse(cardio.isEmpty)
        for s in cardio {
            XCTAssertNotNil(s.cardioDurationMinutes, "\(s.id) should carry a duration")
            XCTAssertNotNil(s.cardioZone, "\(s.id) should carry a target HR zone")
        }
    }

    /// A normal athlete week (≤5 consecutive hard days) gets NO lighter-day
    /// nudge; only a genuinely long observed streak (≥6) attaches one — and even
    /// then the day keeps its scheduled sessions.
    func testLighterRecommendationOnlyAfterLongRealStreak() throws {
        // Normal week: no history → no nudge anywhere.
        let quietFacts = CoachFacts.make(from: [], goal: .hypertrophy,
                                         experience: .intermediate, now: testNow)
        let quietPlan = WeeklyPlan.generate(from: quietFacts, schedulePreferences: exportPrefs)
        XCTAssertFalse(quietPlan.futureDays.flatMap(\.sessions).contains(where: \.recommendsLighter),
                       "A normal week must not be nagged about recovery")

        // 6 consecutive genuinely-hard real days ending today → tomorrow carries
        // the recommendation, but tomorrow is STILL a scheduled training day.
        let ctx = try makeContext()
        var events: [TrainingEvent] = []
        let lifts = ["Bench Press", "Back Squat", "Overhead Press",
                     "Romanian Deadlift", "Barbell Row", "Pull-Up"]
        let muscles = [["chest"], ["quadriceps"], ["delts"],
                       ["hamstrings"], ["lats"], ["biceps"]]
        for i in 0..<6 {
            events.append(try makeStrengthEvent(context: ctx, name: lifts[i],
                                                primaryMuscles: muscles[i],
                                                date: testNow.addingTimeInterval(Double(-i) * 86400 - 3600)))
        }
        let facts = CoachFacts.make(from: events, goal: .hypertrophy,
                                    experience: .intermediate, now: testNow)
        let plan = WeeklyPlan.generate(from: facts, schedulePreferences: exportPrefs)
        guard let tomorrow = plan.tomorrow else { return XCTFail("expected a planned tomorrow") }

        XCTAssertTrue(tomorrow.sessions.contains(where: \.recommendsLighter),
                      "After 6 straight hard days the coach should recommend a lighter day")
        XCTAssertTrue(tomorrow.sessions.contains { !$0.isRest },
                      "The recommendation must not replace the scheduled training day")
        let note = tomorrow.sessions.compactMap(\.adviceNote).first
        XCTAssertNotNil(note)
        XCTAssertTrue(note?.contains("lighter") ?? false, "Advice should read as a suggestion")
    }
}
