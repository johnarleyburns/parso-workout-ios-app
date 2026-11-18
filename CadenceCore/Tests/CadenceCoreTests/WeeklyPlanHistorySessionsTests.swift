import XCTest
import SwiftData
@testable import CadenceCore

/// Coach-user-control Phase 4 — a history day lists EVERY logged workout as its
/// own session chip (a strength AM + boxing PM + run day shows all three), and
/// each chip carries `sourceWorkoutId` so the UI can open that exact workout.
final class WeeklyPlanHistorySessionsTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private var testNow: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 15; comps.hour = 12
        return Calendar.current.date(from: comps) ?? Date(timeIntervalSince1970: 1_784_000_000)
    }

    func testTwoADayHistoryListsEveryWorkoutWithSourceIds() throws {
        let ctx = try makeContext()
        let now = testNow
        let yesterday = now.addingTimeInterval(-86_400)

        let session = try WorkoutRepository.createSession(
            date: yesterday.addingTimeInterval(-10 * 3600), in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(
            named: "Back Squat", primaryMuscles: ["quadriceps"], in: ctx)
        for _ in 0..<3 {
            _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5,
                                             rpe: 8, completedAt: yesterday.addingTimeInterval(-9 * 3600), in: ctx)
        }
        session.endedAt = yesterday.addingTimeInterval(-9 * 3600)
        let strengthEvent = TrainingEvent.from(session: session)!

        let boxing = CardioWorkout(type: .boxing,
                                   start: yesterday.addingTimeInterval(-6 * 3600),
                                   end: yesterday.addingTimeInterval(-5 * 3600),
                                   source: .iphone)
        ctx.insert(boxing)
        let run = CardioWorkout(type: .run,
                                start: yesterday.addingTimeInterval(-3 * 3600),
                                end: yesterday.addingTimeInterval(-2 * 3600),
                                avgHeartRate: 120, source: .iphone)
        ctx.insert(run)
        let boxingEvent = TrainingEvent.from(cardio: boxing)
        let runEvent = TrainingEvent.from(cardio: run)

        let facts = CoachFacts.make(from: [strengthEvent, boxingEvent, runEvent],
                                    goal: .strength, experience: .intermediate, now: now)
        let plan = WeeklyPlan.generate(from: facts)

        let cal = Calendar.current
        let day = try XCTUnwrap(plan.days.first { cal.isDate($0.date, inSameDayAs: yesterday) })

        XCTAssertEqual(day.sessions.count, 3,
                       "All three logged workouts must appear, got \(day.sessions.map(\.label))")
        XCTAssertEqual(day.sessions.filter { $0.kind == .strength }.count, 1)
        XCTAssertTrue(day.sessions.contains { $0.label == "Boxing" })
        XCTAssertTrue(day.sessions.contains { $0.label == "Run" })

        XCTAssertEqual(Set(day.sessions.compactMap(\.sourceWorkoutId)),
                       Set([session.id, boxing.id, run.id]),
                       "Each history chip must link back to its real workout")

        XCTAssertTrue(day.label.contains("Boxing") && day.label.contains("Run"),
                      "The day label must describe every session, got '\(day.label)'")
    }

    func testSameDayCardioSessionsSortedByStartTime() throws {
        let ctx = try makeContext()
        let now = testNow
        let yesterday = now.addingTimeInterval(-86_400)

        let later = CardioWorkout(type: .run,
                                  start: yesterday.addingTimeInterval(-2 * 3600),
                                  end: yesterday.addingTimeInterval(-3600),
                                  avgHeartRate: 120, source: .iphone)
        ctx.insert(later)
        let earlier = CardioWorkout(type: .walk,
                                    start: yesterday.addingTimeInterval(-8 * 3600),
                                    end: yesterday.addingTimeInterval(-7 * 3600),
                                    avgHeartRate: 95, source: .iphone)
        ctx.insert(earlier)

        let facts = CoachFacts.make(from: [TrainingEvent.from(cardio: later),
                                           TrainingEvent.from(cardio: earlier)],
                                    goal: .strength, experience: .intermediate, now: now)
        let plan = WeeklyPlan.generate(from: facts)

        let cal = Calendar.current
        let day = try XCTUnwrap(plan.days.first { cal.isDate($0.date, inSameDayAs: yesterday) })
        XCTAssertEqual(day.sessions.compactMap(\.sourceWorkoutId), [earlier.id, later.id],
                       "Same-day sessions must list in the order they happened")
    }
}
