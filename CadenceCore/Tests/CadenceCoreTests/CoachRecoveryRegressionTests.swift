import XCTest
import SwiftData
@testable import CadenceCore

/// Tests for the recovery-aware CoachDecision engine and eligibility policy.
/// Verifies that recently-trained lifts are properly gated from being recommended again.
final class CoachRecoveryRegressionTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    /// A fixed absolute Thursday (2026-06-25 12:00) so session dates fall within the
    /// Monday-bounded week deterministically, regardless of when the test runs.
    private var testNow: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 25
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps) ?? Date(timeIntervalSince1970: 1_750_000_000)
    }

    // MARK: - Recovery gate tests

    func testNewEngineDeadliftOnly42MinAgoBlocksStrength() throws {
        let ctx = try makeContext()
        let now = testNow
        let session = try deadliftOnlySession(context: ctx, date: now.addingTimeInterval(-42 * 60))
        session.endedAt = now.addingTimeInterval(-40 * 60)
        try ctx.save()
        let event = TrainingEvent.from(session: session)!
        let facts = CoachFacts.make(from: [event], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        XCTAssertNotEqual(decision.primary.kind, .strength,
                          "New engine: should NOT recommend strength 42 min after deadlifting")
        XCTAssertTrue(decision.primary.kind == .easyAerobic || decision.primary.kind == .rest || decision.primary.kind == .recovery,
                      "New engine: should recommend rest or easy aerobic after strength")
    }

    func testNewEngineFullBody42MinAgoNotStrength() throws {
        let ctx = try makeContext()
        let now = testNow
        let session = try fullBodySession(context: ctx, date: now.addingTimeInterval(-42 * 60))
        session.endedAt = now.addingTimeInterval(-40 * 60)
        try ctx.save()
        let event = TrainingEvent.from(session: session)!
        let facts = CoachFacts.make(from: [event], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        XCTAssertNotEqual(decision.primary.kind, .strength,
                          "New engine: should NOT recommend strength 42 min after full-body")
    }

    func testNewEngineDeadlift23h59mAgoIsDeferred() throws {
        let ctx = try makeContext()
        let now = testNow
        let session = try deadliftOnlySession(context: ctx, date: now.addingTimeInterval(-23.98 * 3600))
        session.endedAt = now.addingTimeInterval(-23.97 * 3600)
        try ctx.save()
        let event = TrainingEvent.from(session: session)!
        let facts = CoachFacts.make(from: [event], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        let deferredStrength = decision.deferred.filter { $0.session.kind == .strength }
        XCTAssertFalse(deferredStrength.isEmpty,
                       "New engine: deadlift at 23h59m should be in deferred candidates")
    }

    func testNewEngineDecisionIsDeterministic() throws {
        let ctx = try makeContext()
        let now = testNow
        let session = try deadliftOnlySession(context: ctx, date: now.addingTimeInterval(-3 * 86400))
        session.endedAt = now.addingTimeInterval(-3 * 86400 + 3600)
        try ctx.save()
        let event = TrainingEvent.from(session: session)!
        let facts = CoachFacts.make(from: [event], goal: .strength, experience: .intermediate, now: now)
        let d1 = CoachDecisionEngine.run(facts)
        let d2 = CoachDecisionEngine.run(facts)
        XCTAssertEqual(d1.primary.id, d2.primary.id)
    }

    // MARK: - Card payload integrity

    func testProgressionRecommendationPrescribedSessionIsConcrete() throws {
        let ctx = try makeContext()
        let now = testNow
        _ = try deadliftOnlySession(context: ctx, date: now.addingTimeInterval(-3 * 86_400))
        let session2 = try deadliftOnlySession(context: ctx, date: now.addingTimeInterval(-1 * 86_400),
                                                weight: 105, reps: 5)
        let f = TrainingFacts.make(sessions: [session2], now: now,
                                    goal: .strength, experience: .intermediate)
        let rec = RecommendationEngine.run(f).first { $0.id == "progression.Deadlift" }
        XCTAssertNotNil(rec, "Should have a deadlift progression recommendation")
        let session = rec?.prescribedSession()
        XCTAssertNotNil(session)
        XCTAssertFalse(session?.exerciseNames.isEmpty ?? true, "Prescribed session should name the movement")
        XCTAssertFalse(session?.repLadder.isEmpty ?? true, "Prescribed session should have target reps")
    }

    // MARK: - Helpers

    private func fullBodySession(context: ModelContext, date: Date) throws -> WorkoutSession {
        let session = try WorkoutRepository.createSession(date: date, in: context)
        let squat = try WorkoutRepository.findOrCreateExercise(
            named: "BackSquat", primaryMuscles: ["quadriceps"], secondaryMuscles: ["glutes"], in: context)
        let bench = try WorkoutRepository.findOrCreateExercise(
            named: "BenchPress", primaryMuscles: ["chest"], secondaryMuscles: ["triceps", "front-delts"], in: context)
        let deadlift = try WorkoutRepository.findOrCreateExercise(
            named: "Deadlift", primaryMuscles: ["hamstrings", "lower-back"], secondaryMuscles: ["glutes"], in: context)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 8, in: context)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 8, in: context)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 9, in: context)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 5, rpe: 8, in: context)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 5, rpe: 9, in: context)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 5, rpe: 9, in: context)
        _ = try WorkoutRepository.addSet(to: session, exercise: deadlift, weightKg: 140, reps: 5, rpe: 9, in: context)
        return session
    }

    private func deadliftOnlySession(context: ModelContext, date: Date,
                                      weight: Double = 140, reps: Int = 5) throws -> WorkoutSession {
        let session = try WorkoutRepository.createSession(date: date, in: context)
        let deadlift = try WorkoutRepository.findOrCreateExercise(
            named: "Deadlift", primaryMuscles: ["hamstrings", "lower-back"], secondaryMuscles: ["glutes"], in: context)
        _ = try WorkoutRepository.addSet(to: session, exercise: deadlift, weightKg: weight, reps: reps, rpe: 8, in: context)
        _ = try WorkoutRepository.addSet(to: session, exercise: deadlift, weightKg: weight, reps: reps, rpe: 8, in: context)
        _ = try WorkoutRepository.addSet(to: session, exercise: deadlift, weightKg: weight, reps: reps, rpe: 9, in: context)
        return session
    }
}
