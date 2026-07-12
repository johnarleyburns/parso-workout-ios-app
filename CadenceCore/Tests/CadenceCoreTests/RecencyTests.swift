import XCTest
import SwiftData
@testable import CadenceCore

final class RecencyTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private var testNow: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 11
        comps.hour = 18; comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date(timeIntervalSince1970: 1_750_000_000)
    }

    // MARK: - Soft penalty

    func testSoftPenaltyNonNullForRecentWorkWithoutRPE() throws {
        let ctx = try makeContext()
        let now = testNow
        let today6am = now.addingTimeInterval(-12 * 3600)
        let session = try fullBodyKBSnatchDeadliftSession(context: ctx, date: today6am)
        try ctx.save()
        let event = TrainingEvent.from(session: session)!
        let facts = CoachFacts.make(from: [event], goal: .hypertrophy, experience: .intermediate,
                                     now: now, recoveryAwareCoachV2: true)

        let kbPenalty = facts.recovery.softPenalty(forExerciseNamed: "Double Kettlebell Snatch",
                                                    primaryMuscles: ["delts", "traps"])
        let dlPenalty = facts.recovery.softPenalty(forExerciseNamed: "Deadlift",
                                                    primaryMuscles: ["hamstrings", "lower-back"])

        XCTAssertGreaterThan(kbPenalty, 0, "KB snatch 12h ago (no RPE) should have soft penalty")
        XCTAssertGreaterThan(dlPenalty, 0, "Deadlift 12h ago (no RPE) should have soft penalty")
    }

    func testSoftPenaltyZeroForOldWork() throws {
        let ctx = try makeContext()
        let now = testNow
        let fourDaysAgo = now.addingTimeInterval(-96 * 3600)
        let session = try deadliftSession(context: ctx, date: fourDaysAgo)
        try ctx.save()
        let event = TrainingEvent.from(session: session)!
        let facts = CoachFacts.make(from: [event], goal: .hypertrophy, experience: .intermediate,
                                     now: now, recoveryAwareCoachV2: true)
        let penalty = facts.recovery.softPenalty(forExerciseNamed: "Deadlift",
                                                  primaryMuscles: ["hamstrings", "lower-back"])
        XCTAssertEqual(penalty, 0, "Deadlift 96h ago should have zero soft penalty")
    }

    func testSoftPenaltyUsesCanonicalName() throws {
        let ctx = try makeContext()
        let now = testNow
        let today6am = now.addingTimeInterval(-12 * 3600)
        let session = try fullBodyKBSnatchDeadliftSession(context: ctx, date: today6am)
        try ctx.save()
        let event = TrainingEvent.from(session: session)!
        let facts = CoachFacts.make(from: [event], goal: .hypertrophy, experience: .intermediate,
                                     now: now, recoveryAwareCoachV2: true)
        let penalty = facts.recovery.softPenalty(forExerciseNamed: "Snatch",
                                                  primaryMuscles: ["delts", "traps"])
        XCTAssertGreaterThan(penalty, 0,
                             "Plain 'Snatch' matches canonical form of 'Double Kettlebell Snatch'")
    }

    // MARK: - mostTrainedExercises rotates by recency

    func testMostTrainedExercisesRotatesByRecency() throws {
        let ctx = try makeContext()
        let now = testNow
        let today = now.addingTimeInterval(-6 * 3600)
        let session = try deadliftSession(context: ctx, date: today)
        try ctx.save()
        let session2 = try rdlSession(context: ctx, date: now.addingTimeInterval(-3 * 86400))
        try ctx.save()
        let events = [TrainingEvent.from(session: session)!, TrainingEvent.from(session: session2)!]
        let facts = CoachFacts.make(from: events, goal: .hypertrophy, experience: .intermediate,
                                     now: now, recoveryAwareCoachV2: true)
        let preferred = CoachSession.mostTrainedExercises(facts: facts)
        let hingeName = preferred[.hinge]
        XCTAssertEqual(hingeName, "Romanian Deadlift",
                       "With DL recently done but RDL older, should prefer RDL for hinge")
    }

    // MARK: - Hard-block remains intact

    func testHardBlockStillPreventsRepeatedLift() throws {
        let ctx = try makeContext()
        let now = testNow
        let recent = now.addingTimeInterval(-1 * 3600)
        let session = try deadliftSession(context: ctx, date: recent, rpe: 9)
        try ctx.save()
        let event = TrainingEvent.from(session: session)!
        let facts = CoachFacts.make(from: [event], goal: .hypertrophy, experience: .intermediate, now: now)

        let eligible = facts.recovery.isHardEligible(
            exercise: "Deadlift",
            patterns: MovementPattern.patterns(forExerciseNamed: "Deadlift",
                                                primaryMuscles: ["hamstrings", "lower-back"]),
            bodyParts: BodyPart.parts(forMuscleIDs: ["hamstrings", "lower-back"]),
            now: now)
        XCTAssertFalse(eligible, "Hard block prevents Deadlift re-selection 1h after RPE 9 work")
    }

    // MARK: - End-to-end: optimizer prefers non-recent option

    func testOptimizerPrefersNonRecentExercise() throws {
        let ctx = try makeContext()
        let now = testNow
        let today10am = now.addingTimeInterval(-8 * 3600)

        let session = try deadliftSession(context: ctx, date: today10am)
        try ctx.save()
        let event = TrainingEvent.from(session: session)!
        let coachFacts = CoachFacts.make(from: [event], goal: .hypertrophy, experience: .intermediate,
                                          now: now, recoveryAwareCoachV2: true)

        let trainingFacts = TrainingFacts.make(sessions: [], now: now, goal: .hypertrophy,
                                                experience: .intermediate)

        var comps = Calendar.current.dateComponents([.year, .month, .day], from: now)
        comps.hour = 0; comps.minute = 0
        let todayStart = Calendar.current.date(from: comps) ?? now

        let sessionPlan = CoachSession(
            id: "test.strength", kind: .strength,
            title: "Strength", exercises: [
                CoachSession.RecommendedExercise(name: "Back Squat", sets: 3),
                CoachSession.RecommendedExercise(name: "Romanian Deadlift", sets: 3),
                CoachSession.RecommendedExercise(name: "Bench Press", sets: 3),
                CoachSession.RecommendedExercise(name: "Barbell Row", sets: 3),
                CoachSession.RecommendedExercise(name: "Overhead Press", sets: 3),
                CoachSession.RecommendedExercise(name: "Plank", sets: 2),
            ], launchPayload: .strengthPlan("test"))

        let plan = WeeklyPlan(days: [
            WeeklyPlan.DayOutline(date: todayStart, label: "Today", sessions: [
                PlannedSession(id: "slot", kind: .strength, label: "Strength")
            ], isToday: true, isFuture: true)
        ], generatedAt: now)

        let result = CoachPlanOptimizer.optimize(trainingFacts: trainingFacts, coachFacts: coachFacts,
                                                  weeklyPlan: plan,
                                                  schedulePreferences: .default,
                                                  candidates: [sessionPlan])

        let exercises = result.plannedStrengthSessions.flatMap { $0.exercises ?? [] }
        let names = Set(exercises.map { $0.name })
        XCTAssertFalse(names.contains("Deadlift"),
                       "Optimizer should not pick Deadlift when it was trained 8h ago and RDL was in the template")
    }

    // MARK: - Helpers

    private func fullBodyKBSnatchDeadliftSession(context: ModelContext, date: Date) throws -> WorkoutSession {
        let session = try WorkoutRepository.createSession(date: date, in: context)
        let kbSnatch = try WorkoutRepository.findOrCreateExercise(
            named: "Double Kettlebell Snatch", primaryMuscles: ["delts", "traps"],
            secondaryMuscles: ["hamstrings", "glutes"], in: context)
        let deadlift = try WorkoutRepository.findOrCreateExercise(
            named: "Deadlift", primaryMuscles: ["hamstrings", "lower-back"],
            secondaryMuscles: ["glutes"], in: context)
        for _ in 0..<3 {
            _ = try WorkoutRepository.addSet(to: session, exercise: kbSnatch, weightKg: 24, reps: 8, in: context)
        }
        for _ in 0..<3 {
            _ = try WorkoutRepository.addSet(to: session, exercise: deadlift, weightKg: 140, reps: 5, in: context)
        }
        session.endedAt = date.addingTimeInterval(3600)
        try context.save()
        return session
    }

    private func deadliftSession(context: ModelContext, date: Date, rpe: Double? = nil) throws -> WorkoutSession {
        let session = try WorkoutRepository.createSession(date: date, in: context)
        let deadlift = try WorkoutRepository.findOrCreateExercise(
            named: "Deadlift", primaryMuscles: ["hamstrings", "lower-back"],
            secondaryMuscles: ["glutes"], in: context)
        for _ in 0..<3 {
            _ = try WorkoutRepository.addSet(to: session, exercise: deadlift, weightKg: 140, reps: 5, rpe: rpe, in: context)
        }
        session.endedAt = date.addingTimeInterval(3600)
        try context.save()
        return session
    }

    private func rdlSession(context: ModelContext, date: Date) throws -> WorkoutSession {
        let session = try WorkoutRepository.createSession(date: date, in: context)
        let rdl = try WorkoutRepository.findOrCreateExercise(
            named: "Romanian Deadlift", primaryMuscles: ["hamstrings", "lower-back"],
            secondaryMuscles: ["glutes"], in: context)
        for _ in 0..<3 {
            _ = try WorkoutRepository.addSet(to: session, exercise: rdl, weightKg: 100, reps: 8, in: context)
        }
        session.endedAt = date.addingTimeInterval(3600)
        try context.save()
        return session
    }
}
