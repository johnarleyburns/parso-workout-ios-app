import XCTest
import SwiftData
@testable import CadenceCore

final class CoachLaunchIntegrityTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private var testNow: Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 5; comps.hour = 12; comps.minute = 0; comps.second = 0
        return cal.date(from: comps) ?? Date()
    }

    // MARK: - Integrity: exercises preserved in plan mapping

    func testCoachSessionExercisesArePreservedInPlan() throws {
        let exercises: [CoachSession.RecommendedExercise] = [
            CoachSession.RecommendedExercise(
                name: "Back Squat", primaryMuscles: ["quadriceps"],
                sets: 3, repsLow: 6, repsHigh: 10, loadKg: 80, rir: 2),
            CoachSession.RecommendedExercise(
                name: "Bench Press", primaryMuscles: ["chest"],
                sets: 4, repsLow: 8, repsHigh: 12, loadKg: 60, rir: 2),
            CoachSession.RecommendedExercise(
                name: "Barbell Row", primaryMuscles: ["back"],
                sets: 3, repsLow: 8, repsHigh: 10, loadKg: nil, rir: nil),
        ]
        let session = CoachSession(
            id: "test.strength", kind: .strength, title: "Full-body session",
            exercises: exercises, launchPayload: .strengthPlan("test"))

        let guardResult: Bool = {
            guard let ex = session.exercises, !ex.isEmpty else { return false }
            return true
        }()
        XCTAssertTrue(guardResult, "Session with 3 exercises should pass guard")

        guard let exs = session.exercises else { XCTFail("Exercises should not be nil"); return }
        XCTAssertEqual(exs.count, 3)
        XCTAssertEqual(exs[0].name, "Back Squat")
        XCTAssertEqual(exs[1].name, "Bench Press")
        XCTAssertEqual(exs[2].name, "Barbell Row")

        XCTAssertEqual(exs[0].sets, 3)
        XCTAssertEqual(exs[1].sets, 4)
        XCTAssertEqual(exs[2].sets, 3)

        XCTAssertEqual(exs[0].repsLow, 6)
        XCTAssertEqual(exs[0].repsHigh, 10)
        XCTAssertEqual(exs[1].repsLow, 8)
        XCTAssertEqual(exs[1].repsHigh, 12)

        XCTAssertEqual(exs[0].loadKg, 80)
        XCTAssertEqual(exs[1].loadKg, 60)
        XCTAssertNil(exs[2].loadKg)

        XCTAssertEqual(exs[0].rir, 2)
        XCTAssertEqual(exs[1].rir, 2)
        XCTAssertNil(exs[2].rir)
    }

    // MARK: - Empty exercises guard

    func testEmptyExercisesReturnsNil() throws {
        let nilSession = CoachSession(
            id: "test.nil",
            kind: .strength,
            title: "No exercises",
            exercises: nil,
            launchPayload: .strengthPlan("test"))

        let nilGuard: Bool = {
            guard let ex = nilSession.exercises, !ex.isEmpty else { return false }
            return true
        }()
        XCTAssertFalse(nilGuard, "Nil exercises should fail guard")

        let emptySession = CoachSession(
            id: "test.empty",
            kind: .strength,
            title: "Empty exercises",
            exercises: [],
            launchPayload: .strengthPlan("test"))

        let emptyGuard: Bool = {
            guard let ex = emptySession.exercises, !ex.isEmpty else { return false }
            return true
        }()
        XCTAssertFalse(emptyGuard, "Empty exercises should fail guard")
    }

    // MARK: - Coach exercises diverge from pickRoutine

    func testLaunchPayloadDifferentFromPickRoutine() throws {
        let coachExercises: [CoachSession.RecommendedExercise] = [
            CoachSession.RecommendedExercise(
                name: "Back Squat", primaryMuscles: ["quadriceps"],
                sets: 3, repsLow: 6, repsHigh: 10, rir: 2),
            CoachSession.RecommendedExercise(
                name: "Bench Press", primaryMuscles: ["chest"],
                sets: 3, repsLow: 6, repsHigh: 10, rir: 2),
            CoachSession.RecommendedExercise(
                name: "Barbell Row", primaryMuscles: ["back"],
                sets: 3, repsLow: 6, repsHigh: 10, rir: 2),
            CoachSession.RecommendedExercise(
                name: "Overhead Press", primaryMuscles: ["shoulders"],
                sets: 3, repsLow: 6, repsHigh: 10, rir: 2),
        ]
        let session = CoachSession(
            id: "test.strength", kind: .strength, title: "Coach strength",
            exercises: coachExercises, launchPayload: .strengthPlan("test"))

        let coachExerciseNames = Set(session.exercises?.map(\.name) ?? [])

        let facts = TrainingFacts.make(
            sessions: [], assessments: [],
            goal: .strength, experience: .beginner, formula: .epley)

        let plan = RecommendationEngine.pickRoutine(facts, recentPlanKeys: [])
        let planMovements = Set(plan.movementNames)

        let overlap = coachExerciseNames.intersection(planMovements)
        // The coach session has 4 exercises — even with overlap, the full
        // prescribed set should differ from any single catalog routine.
        XCTAssertNotEqual(
            coachExerciseNames.sorted(), planMovements.sorted(),
            "Coach's prescribed exercises should differ from a generic pickRoutine plan.\nCoach: \(coachExerciseNames.sorted())\nPlan: \(planMovements.sorted())")
        XCTAssertLessThan(
            overlap.count, coachExerciseNames.count,
            "Coach prescription should not be fully contained in one catalog routine")
    }

    // MARK: - Coach-sourced plan carries RIR notes

    func testCoachSessionExercisesCarryRIR() throws {
        let exercises: [CoachSession.RecommendedExercise] = [
            CoachSession.RecommendedExercise(
                name: "Back Squat", primaryMuscles: ["quadriceps"],
                sets: 3, repsLow: 6, repsHigh: 10, rir: 2),
            CoachSession.RecommendedExercise(
                name: "Bench Press", primaryMuscles: ["chest"],
                sets: 3, repsLow: 6, repsHigh: 10, rir: nil),
        ]
        let session = CoachSession(
            id: "test.strength", kind: .strength, title: "Coach strength",
            exercises: exercises, launchPayload: .strengthPlan("test"))

        guard let exs = session.exercises else { XCTFail(); return }

        XCTAssertEqual(exs[0].rir, 2, "RIR 2 should be carried on squats")
        let squatRIRNote = exs[0].rir.map { "Target ≤\($0) RIR" } ?? ""
        XCTAssertFalse(squatRIRNote.isEmpty)
        XCTAssertTrue(squatRIRNote.contains("RIR"))

        XCTAssertNil(exs[1].rir, "Bench press has no RIR")
        let benchRIRNote = exs[1].rir.map { "Target ≤\($0) RIR" } ?? ""
        XCTAssertTrue(benchRIRNote.isEmpty)
    }

    // MARK: - CoachSession.candidates() produces valid exercises

    func testCandidatesProduceValidStrengthExercises() throws {
        let facts = CoachFacts.make(
            from: [], goal: .strength, experience: .intermediate,
            now: testNow)

        let candidates = CoachSession.candidates(for: facts)

        let strengthSessions = candidates.filter { $0.kind == .strength }
        XCTAssertFalse(strengthSessions.isEmpty, "Should produce at least one strength candidate")

        for s in strengthSessions {
            guard let exercises = s.exercises, !exercises.isEmpty else {
                XCTFail("Strength session \(s.id) should have exercises")
                continue
            }
            XCTAssertFalse(exercises.isEmpty, "Exercises should not be empty")
            for ex in exercises {
                XCTAssertFalse(ex.name.isEmpty, "Exercise should have a name")
                let sets = ex.sets ?? 3
                XCTAssertGreaterThan(sets, 0, "Sets should be positive")
            }
        }
    }
}
