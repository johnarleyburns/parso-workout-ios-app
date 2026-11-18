import XCTest
import SwiftData
@testable import CadenceCore

/// P7 (issue 7) — a completed day that had BOTH strength and cardio must describe
/// the sessions, never collapse to a bare weekday name like "Thu".
final class WeeklyPlanLabelTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    func testCompletedStrengthPlusCardioDayIsNotAWeekdayName() throws {
        let ctx = try makeContext()
        // Anchor "now" to a fixed Thursday; the strength+cardio day is yesterday
        // (Wednesday) so it lands in the history window as a past, completed day.
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 25; comps.hour = 12
        let now = Calendar.current.date(from: comps)!
        let yesterday = now.addingTimeInterval(-86_400)

        // A completed strength session yesterday.
        let session = try WorkoutRepository.createSession(date: yesterday.addingTimeInterval(-3600), in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(named: "Back Squat", primaryMuscles: ["quadriceps"], in: ctx)
        for _ in 0..<3 {
            _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5,
                                             rpe: 8, completedAt: yesterday.addingTimeInterval(-1800), in: ctx)
        }
        session.endedAt = yesterday.addingTimeInterval(-600)
        let strengthEvent = TrainingEvent.from(session: session)!

        // A cardio run yesterday.
        let cardio = CardioWorkout(type: .run, start: yesterday.addingTimeInterval(-7200),
                                   end: yesterday.addingTimeInterval(-5400), avgHeartRate: 140, source: .iphone)
        ctx.insert(cardio)
        let cardioEvent = TrainingEvent.from(cardio: cardio)

        let facts = CoachFacts.make(from: [strengthEvent, cardioEvent],
                                    goal: .strength, experience: .intermediate, now: now)
        let plan = WeeklyPlan.generate(from: facts)

        // Find yesterday's day outline.
        let cal = Calendar.current
        guard let day = plan.days.first(where: { cal.isDate($0.date, inSameDayAs: yesterday) }) else {
            return XCTFail("yesterday should be in the plan history window")
        }
        XCTAssertFalse(day.sessions.isEmpty, "past strength+cardio day should carry its sessions")

        let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        XCTAssertFalse(weekdayNames.contains(day.label),
                       "A completed strength+cardio day must describe the work, not read '\(day.label)'")
        XCTAssertTrue(day.label.localizedCaseInsensitiveContains("strength"),
                      "Label should mention the strength session, got '\(day.label)'")
    }
}
