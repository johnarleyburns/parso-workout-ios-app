import XCTest
import SwiftData
@testable import CadenceCore

final class CoachDecisionEngineTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private var testNow: Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 5; comps.hour = 12; comps.minute = 0; comps.second = 0
        return cal.date(from: comps) ?? Date()
    }

    private func makeStrengthEvent(context: ModelContext, name: String,
                                    primaryMuscles: [String], date: Date, sets: Int = 3,
                                    rpe: Double? = 8) throws -> TrainingEvent {
        let session = try WorkoutRepository.createSession(date: date.addingTimeInterval(-600), in: context)
        let ex = try WorkoutRepository.findOrCreateExercise(
            named: name, primaryMuscles: primaryMuscles, in: context)
        for _ in 0..<sets {
            _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 100, reps: 5, rpe: rpe, in: context)
        }
        session.endedAt = date
        return TrainingEvent.from(session: session)!
    }

    private func makeCardioEvent(context: ModelContext, type: CardioType, date: Date,
                                  duration: TimeInterval, avgHR: Double?) -> TrainingEvent {
        let cardio = CardioWorkout(type: type, start: date.addingTimeInterval(-duration),
                                    end: date, avgHeartRate: avgHR, source: .iphone)
        context.insert(cardio)
        return TrainingEvent.from(cardio: cardio)
    }

    // MARK: - Balance decisions

    func testTwoStrengthDaysZeroAerobicPrefersAerobic() throws {
        let ctx = try makeContext()
        let now = testNow
        let s1 = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                        date: now.addingTimeInterval(-3 * 86400))
        let s2 = try makeStrengthEvent(context: ctx, name: "Bench", primaryMuscles: ["chest"],
                                        date: now.addingTimeInterval(-6 * 86400))
        let facts = CoachFacts.make(from: [s1, s2], goal: .strength, experience: .intermediate, now: now)

        let decision = CoachDecisionEngine.run(facts)
        XCTAssertTrue(decision.primary.kind == .moderateAerobic || decision.primary.kind == .easyAerobic,
                      "With 2 strength days and 0 aerobic, primary should be aerobic. Got: \(decision.primary.kind)")
    }

    func testZeroStrengthDaysOneFiftyAerobicPrefersStrength() throws {
        let ctx = try makeContext()
        let now = testNow
        let runs: [TrainingEvent] = [
            makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-1 * 86400), duration: 3600, avgHR: 140),
            makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-2 * 86400), duration: 3600, avgHR: 140),
            makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-3 * 86400), duration: 3600, avgHR: 140),
        ]
        let facts = CoachFacts.make(from: runs, goal: .strength, experience: .intermediate, now: now)

        let decision = CoachDecisionEngine.run(facts)
        XCTAssertEqual(decision.primary.kind, .strength,
                       "With 0 strength and aerobic met, primary should be strength. Got: \(decision.primary.kind)")
    }

    // MARK: - Pain concern

    func testPainConcernBlocksHardTraining() throws {
        let ctx = try makeContext()
        let now = testNow
        let events: [TrainingEvent] = []
        let facts = CoachFacts.make(from: events, goal: .strength, experience: .intermediate, now: now)

        let decision = CoachDecisionEngine.run(facts, hasPainConcern: true)
        XCTAssertEqual(decision.primary.kind, .rest)
        XCTAssertFalse(decision.warnings.isEmpty)
    }

    // MARK: - Beginner

    func testBeginnerGetsBeginnerSessions() throws {
        let ctx = try makeContext()
        let now = testNow
        let events: [TrainingEvent] = []
        let facts = CoachFacts.make(from: events, goal: .strength, experience: .beginner, now: now)

        let decision = CoachDecisionEngine.run(facts)
        let candidates = CoachSession.candidates(for: facts)
        XCTAssertTrue(candidates.contains { $0.id == "strength.beginnerA" })
        XCTAssertTrue(candidates.contains { $0.id == "strength.beginnerB" })
    }

    // MARK: - Determinism

    func testDecisionIsDeterministic() throws {
        let ctx = try makeContext()
        let now = testNow
        let s1 = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                        date: now.addingTimeInterval(-3 * 86400))
        let facts = CoachFacts.make(from: [s1], goal: .strength, experience: .intermediate, now: now)

        let d1 = CoachDecisionEngine.run(facts)
        let d2 = CoachDecisionEngine.run(facts)
        XCTAssertEqual(d1.primary.id, d2.primary.id)
    }

    // MARK: - WeeklyPlan generation

    func testWeeklyPlanIncludesSevenDays() throws {
        let ctx = try makeContext()
        let now = testNow
        let events: [TrainingEvent] = []
        let facts = CoachFacts.make(from: events, goal: .strength, experience: .intermediate, now: now)

        let plan = WeeklyPlan.generate(from: facts)
        XCTAssertEqual(plan.days.count, 7)
        XCTAssertTrue(plan.days.contains { $0.isToday })
    }

    func testWeeklyPlanShowsCompletedDays() throws {
        let ctx = try makeContext()
        let now = testNow
        let s1 = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                        date: now.addingTimeInterval(-2 * 86400))
        let facts = CoachFacts.make(from: [s1], goal: .strength, experience: .intermediate, now: now)

        let plan = WeeklyPlan.generate(from: facts)
        let completed = plan.days.filter(\.isCompleted)
        XCTAssertFalse(completed.isEmpty)
    }
}
