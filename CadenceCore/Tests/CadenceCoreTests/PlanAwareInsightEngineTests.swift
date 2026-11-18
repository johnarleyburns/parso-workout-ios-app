import XCTest
import SwiftData
@testable import CadenceCore

final class PlanAwareInsightEngineTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private func absPlannedSession(sets: Int) -> CoachSession {
        CoachSession(
            id: "test.abs",
            kind: .strength,
            title: "Core",
            exercises: [
                CoachSession.RecommendedExercise(
                    name: "Plank",
                    primaryMuscles: ["abs"],
                    sets: sets
                )
            ],
            launchPayload: .strengthPlan("test"))
    }

    private func earlyWeekTuesday() -> Date {
        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.year = 2026
        comps.month = 6
        comps.day = 23
        comps.hour = 12
        return comps.date ?? Date(timeIntervalSince1970: 1_782_388_800)
    }

    private func lateWeekThursday() -> Date {
        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.year = 2026
        comps.month = 6
        comps.day = 25
        comps.hour = 12
        return comps.date ?? Date(timeIntervalSince1970: 1_782_388_800)
    }

    // MARK: - Early week + projected volume meets MEV → no nag

    func testEarlyWeekProjectedAbsMeetsMEVNoInsight() throws {
        let now = earlyWeekTuesday()
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-86_400), in: ctx)
        let chest = try WorkoutRepository.findOrCreateExercise(
            named: "TestChest", primaryMuscles: ["chest"], in: ctx)
        for _ in 0..<8 {
            _ = try WorkoutRepository.addSet(to: session, exercise: chest, weightKg: 50, reps: 8, rpe: 7, in: ctx)
        }
        let facts = TrainingFacts.make(sessions: [session], now: now, goal: .hypertrophy,
                                        experience: .intermediate)

        let insights = PlanAwareInsightEngine.run(
            completed: facts,
            plan: WeeklyPlan(days: [], generatedAt: now),
            plannedStrengthSessions: [absPlannedSession(sets: 6)],
            now: now)

        let absInsight = insights.first { $0.id == "volume.abdominals" }
        XCTAssertNil(absInsight,
                     "Abs with 0 done + 6 planned = 6 projected (MEV 6 for intermediate) should NOT produce a projected-low nag")
    }

    // MARK: - Early week + projected volume below MEV → insight with "to go", never "target met"

    func testEarlyWeekProjectedBelowMEVShowsInsightWithToGoNotTargetMet() throws {
        let now = earlyWeekTuesday()
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-86_400), in: ctx)
        let chest = try WorkoutRepository.findOrCreateExercise(
            named: "TestChest", primaryMuscles: ["chest"], in: ctx)
        for _ in 0..<4 {
            _ = try WorkoutRepository.addSet(to: session, exercise: chest, weightKg: 50, reps: 8, rpe: 7, in: ctx)
        }
        let facts = TrainingFacts.make(sessions: [session], now: now, goal: .hypertrophy,
                                        experience: .intermediate)

        let insights = PlanAwareInsightEngine.run(
            completed: facts,
            plan: WeeklyPlan(days: [], generatedAt: now),
            plannedStrengthSessions: [absPlannedSession(sets: 3)],
            now: now)

        let absInsight = insights.first { $0.id == "volume.abdominals" }
        XCTAssertNotNil(absInsight,
                        "Abs with 0 done + 3 planned = 3 projected (MEV 6) should produce a projected-low nag")
        XCTAssertTrue(absInsight?.message.contains("to go") ?? false,
                      "Insight message should contain 'to go' when below target, got: \(absInsight?.message ?? "nil")")
        XCTAssertFalse(absInsight?.message.contains("target met") ?? true,
                       "Insight message should NEVER contain 'target met' for a below-MEV part, got: \(absInsight?.message ?? "nil")")
    }

    // MARK: - Regression: exact Abs 0-done / 6-planned / MEV 6 scenario

    func testAbsZeroDoneSixPlannedMEVSixNoNag() throws {
        let now = earlyWeekTuesday()
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-86_400), in: ctx)
        let chest = try WorkoutRepository.findOrCreateExercise(
            named: "TestChest", primaryMuscles: ["chest"], in: ctx)
        for _ in 0..<8 {
            _ = try WorkoutRepository.addSet(to: session, exercise: chest, weightKg: 50, reps: 8, rpe: 7, in: ctx)
        }
        let facts = TrainingFacts.make(sessions: [session], now: now, goal: .hypertrophy,
                                        experience: .intermediate)

        let insights = PlanAwareInsightEngine.run(
            completed: facts,
            plan: WeeklyPlan(days: [], generatedAt: now),
            plannedStrengthSessions: [absPlannedSession(sets: 6)],
            now: now)

        let absInsight = insights.first { $0.id == "volume.abdominals" }
        XCTAssertNil(absInsight,
                     "Abs 0 done + 6 planned = 6 projected vs MEV 6 should NOT produce any insight — regression test for contradictory 'projected low … target met'")
    }

    // MARK: - Late week: projected below MEV still produces insight with "to go"

    func testLateWeekProjectedLowStillShowsToGo() throws {
        let now = lateWeekThursday()
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-86_400), in: ctx)
        let chest = try WorkoutRepository.findOrCreateExercise(
            named: "TestChest", primaryMuscles: ["chest"], in: ctx)
        for _ in 0..<4 {
            _ = try WorkoutRepository.addSet(to: session, exercise: chest, weightKg: 50, reps: 8, rpe: 7, in: ctx)
        }
        let facts = TrainingFacts.make(sessions: [session], now: now, goal: .hypertrophy,
                                        experience: .intermediate)

        let insights = PlanAwareInsightEngine.run(
            completed: facts,
            plan: WeeklyPlan(days: [], generatedAt: now),
            plannedStrengthSessions: [absPlannedSession(sets: 2)],
            now: now)

        let absInsight = insights.first { $0.id == "volume.abdominals" }
        let chestInsight = insights.first { $0.id == "volume.chest" }
        XCTAssertNotNil(absInsight,
                        "Late week: Abs projected below MEV should still produce a projected-low insight")
        XCTAssertTrue(absInsight?.message.contains("to go") ?? false,
                      "Late week projected-low message should contain 'to go'")
        XCTAssertNotNil(chestInsight, "Chest at 4 sets (below MEV 8) should still get an insight")
    }

    // MARK: - Late week: projected meets MEV suppresses insight (same guard)

    func testLateWeekProjectedMeetsMEVNoInsight() throws {
        let now = lateWeekThursday()
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-86_400), in: ctx)
        let chest = try WorkoutRepository.findOrCreateExercise(
            named: "TestChest", primaryMuscles: ["chest"], in: ctx)
        for _ in 0..<4 {
            _ = try WorkoutRepository.addSet(to: session, exercise: chest, weightKg: 50, reps: 8, rpe: 7, in: ctx)
        }
        let facts = TrainingFacts.make(sessions: [session], now: now, goal: .hypertrophy,
                                        experience: .intermediate)

        let insights = PlanAwareInsightEngine.run(
            completed: facts,
            plan: WeeklyPlan(days: [], generatedAt: now),
            plannedStrengthSessions: [absPlannedSession(sets: 8)],
            now: now)

        let absInsight = insights.first { $0.id == "volume.abdominals" }
        XCTAssertNil(absInsight,
                     "Late week: Abs 0 done + 8 planned = 8 projected (MEV 6) should NOT produce a projected-low nag — plan covers it")
    }
}
