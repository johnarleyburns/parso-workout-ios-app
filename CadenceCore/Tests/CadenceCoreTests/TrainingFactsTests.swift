import XCTest
import SwiftData
@testable import CadenceCore

/// strength-pivot P3 — the engine's computed snapshot from logged history.
final class TrainingFactsTests: XCTestCase {

    /// A known Thursday at noon so session dates fall within the Monday-bounded week
    /// regardless of what real day the test runs.
    private var testNow: Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 5  // Thursday
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        return cal.date(from: comps) ?? Date()
    }

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    /// Bench with primary chest + secondary triceps/front-delts: primary counts 1.0,
    /// secondary 0.5 each; warmups and zero-rep sets excluded.
    func testWeeklySetsCountPrimaryFullSecondaryHalf() throws {
        let ctx = try makeContext()
        let now = testNow
        let s = try WorkoutRepository.createSession(date: now.addingTimeInterval(-2 * 86_400), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(
            named: "Test Bench", primaryMuscles: ["chest"],
            secondaryMuscles: ["triceps", "front-delts"], in: ctx)
        for _ in 0..<4 {
            _ = try WorkoutRepository.addSet(to: s, exercise: bench, weightKg: 80, reps: 5, in: ctx)
        }
        _ = try WorkoutRepository.addSet(to: s, exercise: bench, weightKg: 40, reps: 5, isWarmup: true, in: ctx)

        let facts = TrainingFacts.make(sessions: [s], now: now, goal: .hypertrophy, experience: .intermediate)
        XCTAssertEqual(facts.weeklySetsByPart[.chest] ?? -1, 4.0, accuracy: 0.001)      // primary
        XCTAssertEqual(facts.weeklySetsByPart[.triceps] ?? -1, 2.0, accuracy: 0.001)    // secondary 0.5×4
        XCTAssertEqual(facts.weeklySetsByPart[.shoulders] ?? -1, 2.0, accuracy: 0.001)  // front-delts → shoulders
        XCTAssertEqual(facts.totalWorkingSets, 4)
    }

    func testStaleSessionsExcludedFromWeeklyWindow() throws {
        let ctx = try makeContext()
        let now = testNow
        let old = try WorkoutRepository.createSession(date: now.addingTimeInterval(-10 * 86_400), in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(named: "Test Squat", primaryMuscles: ["quads"], in: ctx)
        _ = try WorkoutRepository.addSet(to: old, exercise: squat, weightKg: 100, reps: 5, in: ctx)

        let facts = TrainingFacts.make(sessions: [old], now: now, goal: .strength, experience: .intermediate)
        XCTAssertNil(facts.weeklySetsByPart[.legs])
        XCTAssertEqual(facts.totalWorkingSets, 0)
    }

    func testFrequencyCountsDistinctDays() throws {
        let ctx = try makeContext()
        let now = testNow
        let squat = try WorkoutRepository.findOrCreateExercise(named: "Test Squat 2", primaryMuscles: ["quads"], in: ctx)
        let day1 = try WorkoutRepository.createSession(date: now.addingTimeInterval(-2 * 86_400), in: ctx)
        let day3 = try WorkoutRepository.createSession(date: now.addingTimeInterval(-3 * 86_400), in: ctx)
        _ = try WorkoutRepository.addSet(to: day1, exercise: squat, weightKg: 100, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: day3, exercise: squat, weightKg: 100, reps: 5, in: ctx)

        let facts = TrainingFacts.make(sessions: [day1, day3], now: now, goal: .strength, experience: .intermediate)
        XCTAssertEqual(facts.frequencyByPart[.legs], 2)
    }

    func testE1RMTrendRisingAcrossWindows() throws {
        let ctx = try makeContext()
        let now = testNow
        let dl = try WorkoutRepository.findOrCreateExercise(named: "Test Deadlift", primaryMuscles: ["hamstrings"], in: ctx)
        let prior = try WorkoutRepository.createSession(date: now.addingTimeInterval(-8 * 86_400), in: ctx)
        let recent = try WorkoutRepository.createSession(date: now.addingTimeInterval(-2 * 86_400), in: ctx)
        _ = try WorkoutRepository.addSet(to: prior, exercise: dl, weightKg: 100, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: recent, exercise: dl, weightKg: 115, reps: 5, in: ctx)

        let facts = TrainingFacts.make(sessions: [prior, recent], now: now, goal: .strength, experience: .intermediate)
        XCTAssertEqual(facts.e1RMTrendByExercise["Test Deadlift"], .rising)
    }

    func testE1RMTrendFlatWithinNoiseBand() throws {
        let ctx = try makeContext()
        let now = testNow
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Test OHP", primaryMuscles: ["delts"], in: ctx)
        let prior = try WorkoutRepository.createSession(date: now.addingTimeInterval(-8 * 86_400), in: ctx)
        let recent = try WorkoutRepository.createSession(date: now.addingTimeInterval(-2 * 86_400), in: ctx)
        _ = try WorkoutRepository.addSet(to: prior, exercise: ex, weightKg: 60, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: recent, exercise: ex, weightKg: 60, reps: 5, in: ctx)

        let facts = TrainingFacts.make(sessions: [prior, recent], now: now, goal: .strength, experience: .intermediate)
        XCTAssertEqual(facts.e1RMTrendByExercise["Test OHP"], .flat)
    }

    func testAvgRPEAndDerivedRIR() throws {
        let ctx = try makeContext()
        let now = testNow
        let s = try WorkoutRepository.createSession(date: now.addingTimeInterval(-2 * 86_400), in: ctx)
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Test Row", primaryMuscles: ["lats"], in: ctx)
        _ = try WorkoutRepository.addSet(to: s, exercise: ex, weightKg: 80, reps: 8, rpe: 7, in: ctx)
        _ = try WorkoutRepository.addSet(to: s, exercise: ex, weightKg: 80, reps: 8, rpe: 9, in: ctx)

        let facts = TrainingFacts.make(sessions: [s], now: now, goal: .hypertrophy, experience: .intermediate)
        XCTAssertEqual(facts.avgRPE ?? -1, 8.0, accuracy: 0.001)
        XCTAssertEqual(facts.avgRIR ?? -1, 2.0, accuracy: 0.001)
    }

    func testIntensityDistributionRelativeToBest() throws {
        let ctx = try makeContext()
        let now = testNow
        let s = try WorkoutRepository.createSession(date: now.addingTimeInterval(-2 * 86_400), in: ctx)
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Test Bench 2", primaryMuscles: ["chest"], in: ctx)
        // Best single set this week defines the reference; the heavy single set is
        // ~100% of its own e1RM, the light one well under 60%.
        _ = try WorkoutRepository.addSet(to: s, exercise: ex, weightKg: 100, reps: 3, in: ctx)
        _ = try WorkoutRepository.addSet(to: s, exercise: ex, weightKg: 40, reps: 3, in: ctx)

        let facts = TrainingFacts.make(sessions: [s], now: now, goal: .strength, experience: .intermediate)
        XCTAssertEqual(facts.intensity.sampleCount, 2)
        XCTAssertGreaterThan(facts.intensity.heavy, 0)
        XCTAssertGreaterThan(facts.intensity.light, 0)
    }

    func testDaysSinceLastSession() throws {
        let ctx = try makeContext()
        let now = testNow
        let s = try WorkoutRepository.createSession(date: now.addingTimeInterval(-3 * 86_400), in: ctx)
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Test Curl", primaryMuscles: ["biceps"], in: ctx)
        _ = try WorkoutRepository.addSet(to: s, exercise: ex, weightKg: 20, reps: 10, in: ctx)

        let facts = TrainingFacts.make(sessions: [s], now: now, goal: .hypertrophy, experience: .intermediate)
        XCTAssertEqual(facts.daysSinceLastSession, 3)
    }
}
