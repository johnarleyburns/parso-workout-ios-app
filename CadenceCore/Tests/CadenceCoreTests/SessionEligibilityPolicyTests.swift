import XCTest
import SwiftData
@testable import CadenceCore

final class SessionEligibilityPolicyTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private var testNow: Date {
        // Fixed absolute Thursday (2026-06-25 12:00) — deterministic, no wall-clock drift.
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 25
        comps.hour = 12; comps.minute = 0; comps.second = 0
        return Calendar.current.date(from: comps) ?? Date(timeIntervalSince1970: 1_750_000_000)
    }

    private func makeFacts(events: [TrainingEvent], now: Date? = nil) -> CoachFacts {
        CoachFacts.make(from: events, goal: .strength, experience: .intermediate,
                         now: now ?? testNow)
    }

    private func makeStrengthCandidate(exercises: [CoachSession.RecommendedExercise]? = nil) -> CoachSession {
        CoachSession(
            id: "test.strength", kind: .strength, title: "Test strength",
            exercises: exercises ?? [CoachSession.RecommendedExercise(name: "Back Squat", primaryMuscles: ["quadriceps"])],
            launchPayload: .strengthPlan("test")
        )
    }

    private func makeAerobicCandidate(kind: CoachSessionKind = .easyAerobic) -> CoachSession {
        CoachSession(
            id: "test.aerobic", kind: kind, title: "Test aerobic",
            modality: .walk, intensity: .easy, launchPayload: .cardio(type: "walk", durationMinutes: 30)
        )
    }

    // MARK: - R1/R2/R3: Lift recovery gates

    func testFullBody42MinAgoBlocksStrengthSession() throws {
        let ctx = try makeContext()
        let now = testNow
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-42 * 60), in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(
            named: "Back Squat", primaryMuscles: ["quadriceps"], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 8, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 8, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 9, in: ctx)
        session.endedAt = now.addingTimeInterval(-40 * 60)
        try ctx.save()

        let event = TrainingEvent.from(session: session)!
        let facts = makeFacts(events: [event], now: now)

        let candidate = makeStrengthCandidate()
        let result = SessionEligibilityPolicy.evaluate(candidate, facts: facts)

        guard case .deferred(_, let reasons) = result else {
            XCTFail("Expected defer for strength session 42min after full-body"); return
        }
        XCTAssertFalse(reasons.isEmpty, "Should have at least one reason")
    }

    func testStrengthDeferralUsesRecoveryWindowNotCurrentTime() throws {
        let ctx = try makeContext()
        let now = testNow
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-2 * 3600), in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(
            named: "Back Squat", primaryMuscles: ["quadriceps"], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 8, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 8, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 8, in: ctx)
        session.endedAt = now.addingTimeInterval(-1.9 * 3600)
        try ctx.save()

        let event = TrainingEvent.from(session: session)!
        let facts = makeFacts(events: [event], now: now)

        let result = SessionEligibilityPolicy.evaluate(makeStrengthCandidate(), facts: facts)
        guard case .deferred(let until, _) = result else {
            XCTFail("Expected defer for recent hard squat"); return
        }
        let expected = facts.recovery.byExercise["Back Squat"]?.hardEligibleAt
        XCTAssertEqual(until.timeIntervalSince1970, expected?.timeIntervalSince1970 ?? 0, accuracy: 1)
        XCTAssertGreaterThan(until, now)
    }

    func testDeadlift23h59mAgoBlocksExactDeadlift() throws {
        let ctx = try makeContext()
        let now = testNow
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-23.98 * 3600), in: ctx)
        let dl = try WorkoutRepository.findOrCreateExercise(
            named: "Deadlift", primaryMuscles: ["hamstrings", "lower-back"], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: dl, weightKg: 140, reps: 5, rpe: 9, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: dl, weightKg: 140, reps: 5, rpe: 9, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: dl, weightKg: 140, reps: 5, rpe: 9, in: ctx)
        session.endedAt = now.addingTimeInterval(-23.97 * 3600)
        try ctx.save()

        let event = TrainingEvent.from(session: session)!
        let facts = makeFacts(events: [event], now: now)

        let candidate = CoachSession(
            id: "test.deadlift", kind: .strength, title: "Deadlift session",
            exercises: [CoachSession.RecommendedExercise(name: "Deadlift", primaryMuscles: ["hamstrings", "lower-back"])],
            launchPayload: .strengthPlan("deadlift")
        )
        let result = SessionEligibilityPolicy.evaluate(candidate, facts: facts)
        guard case .deferred = result else {
            XCTFail("Expected defer for deadlift 23h59m ago"); return
        }
    }

    func testDeadlift24h01mAgoPosteriorChainStillBlocked() throws {
        let ctx = try makeContext()
        let now = testNow
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-24.02 * 3600), in: ctx)
        let dl = try WorkoutRepository.findOrCreateExercise(
            named: "Deadlift", primaryMuscles: ["hamstrings", "lower-back"], in: ctx)
        for _ in 0..<5 {
            _ = try WorkoutRepository.addSet(to: session, exercise: dl, weightKg: 140, reps: 5, rpe: 9, in: ctx)
        }
        session.endedAt = now.addingTimeInterval(-24.01 * 3600)
        try ctx.save()

        let event = TrainingEvent.from(session: session)!
        let facts = makeFacts(events: [event], now: now)

        let candidate = CoachSession(
            id: "test.deadlift", kind: .strength, title: "Deadlift session",
            exercises: [CoachSession.RecommendedExercise(name: "Deadlift", primaryMuscles: ["hamstrings", "lower-back"])],
            launchPayload: .strengthPlan("deadlift")
        )
        let result = SessionEligibilityPolicy.evaluate(candidate, facts: facts)
        guard case .deferred = result else {
            XCTFail("Expected pattern-gate defer at 24h01m"); return
        }
    }

    // MARK: - R4: Technique work vs hard progression

    func testLowVolumeTechniqueWorkWithGoodReadinessIsEligible() throws {
        let ctx = try makeContext()
        let now = testNow
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-26 * 3600), in: ctx)
        let dl = try WorkoutRepository.findOrCreateExercise(
            named: "Deadlift", primaryMuscles: ["hamstrings", "lower-back"], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: dl, weightKg: 80, reps: 3, rpe: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: dl, weightKg: 80, reps: 3, rpe: 5, in: ctx)
        session.endedAt = now.addingTimeInterval(-25.9 * 3600)
        try ctx.save()

        let event = TrainingEvent.from(session: session)!
        let facts = makeFacts(events: [event], now: now)

        let candidate = CoachSession(
            id: "test.light", kind: .strength, title: "Light technique work",
            exercises: [CoachSession.RecommendedExercise(name: "Deadlift", primaryMuscles: ["hamstrings", "lower-back"])],
            launchPayload: .strengthPlan("light")
        )
        let result = SessionEligibilityPolicy.evaluate(candidate, facts: facts)
        guard case .eligible = result else {
            XCTFail("Low-volume technique work >24h should be eligible"); return
        }
    }

    // MARK: - R6: Upper body strength, lower easy aerobic

    func testUpperBodyStrengthYesterdayAllowsEasyRun() throws {
        let ctx = try makeContext()
        let now = testNow
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-25 * 3600), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(
            named: "Bench Press", primaryMuscles: ["chest"], secondaryMuscles: ["triceps"], in: ctx)
        for _ in 0..<5 {
            _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 5, rpe: 8, in: ctx)
        }
        session.endedAt = now.addingTimeInterval(-24.9 * 3600)
        try ctx.save()

        let event = TrainingEvent.from(session: session)!
        let facts = makeFacts(events: [event], now: now)

        let candidate = makeAerobicCandidate(kind: .easyAerobic)
        let result = SessionEligibilityPolicy.evaluate(candidate, facts: facts)
        guard case .eligible = result else {
            XCTFail("Easy run should be eligible after upper-body only strength"); return
        }
    }

    func testUpperBodyStrengthBlocksHardFullBodyWithBench() throws {
        let ctx = try makeContext()
        let now = testNow
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-2 * 3600), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(
            named: "Bench Press", primaryMuscles: ["chest"], in: ctx)
        for _ in 0..<5 {
            _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 5, rpe: 9, in: ctx)
        }
        session.endedAt = now.addingTimeInterval(-1.9 * 3600)
        try ctx.save()

        let event = TrainingEvent.from(session: session)!
        let facts = makeFacts(events: [event], now: now)

        let fullBody = CoachSession(
            id: "test.fullbody", kind: .strength, title: "Full body",
            exercises: [
                CoachSession.RecommendedExercise(name: "Back Squat", primaryMuscles: ["quadriceps"]),
                CoachSession.RecommendedExercise(name: "Bench Press", primaryMuscles: ["chest"]),
            ],
            launchPayload: .strengthPlan("fullBody")
        )
        let result = SessionEligibilityPolicy.evaluate(fullBody, facts: facts)
        guard case .deferred = result else {
            XCTFail("Full-body with bench should be deferred after recent bench"); return
        }
    }

    // MARK: - R7: Lower-body strength blocks hard cardio

    func testLowerBodyStrengthTodayBlocksHardRun() throws {
        let ctx = try makeContext()
        let now = testNow
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-3 * 3600), in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(
            named: "Back Squat", primaryMuscles: ["quadriceps"], in: ctx)
        for _ in 0..<6 {
            _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 9, in: ctx)
        }
        session.endedAt = now.addingTimeInterval(-2.9 * 3600)
        try ctx.save()

        let event = TrainingEvent.from(session: session)!
        let facts = makeFacts(events: [event], now: now)

        let hardRun = makeAerobicCandidate(kind: .moderateAerobic)
        let result = SessionEligibilityPolicy.evaluate(hardRun, facts: facts)
        guard case .deferred = result else {
            XCTFail("Hard run should be deferred after lower-body strength"); return
        }
    }

    func testLowerBodyStrengthAllowsEasyWalk() throws {
        let ctx = try makeContext()
        let now = testNow
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-3 * 3600), in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(
            named: "Back Squat", primaryMuscles: ["quadriceps"], in: ctx)
        for _ in 0..<6 {
            _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 9, in: ctx)
        }
        session.endedAt = now.addingTimeInterval(-2.9 * 3600)
        try ctx.save()

        let event = TrainingEvent.from(session: session)!
        let facts = makeFacts(events: [event], now: now)

        let easyWalk = makeAerobicCandidate(kind: .easyAerobic)
        let result = SessionEligibilityPolicy.evaluate(easyWalk, facts: facts)
        guard case .eligible = result else {
            XCTFail("Easy walk should be eligible even after lower-body strength"); return
        }
    }
}
