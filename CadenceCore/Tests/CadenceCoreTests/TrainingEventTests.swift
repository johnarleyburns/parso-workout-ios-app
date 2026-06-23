import XCTest
import SwiftData
@testable import CadenceCore

final class TrainingEventTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private var testNow: Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 5; comps.hour = 12; comps.minute = 0; comps.second = 0
        return cal.date(from: comps) ?? Date()
    }

    func testStrengthSessionToTrainingEvent() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(date: testNow.addingTimeInterval(-3600), in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(
            named: "Back Squat", primaryMuscles: ["quadriceps"], secondaryMuscles: ["glutes"], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 8, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 9, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 9, in: ctx)
        session.endedAt = testNow.addingTimeInterval(-3300)
        try ctx.save()

        let event = TrainingEvent.from(session: session)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.source, .appStrength)
        XCTAssertEqual(event?.completion, .completed)

        guard case .strength(let details) = event?.kind, let d = details else {
            XCTFail("Expected strength event"); return
        }
        XCTAssertEqual(d.exercises.count, 1)
        let ex = d.exercises.first!
        XCTAssertEqual(ex.exerciseName, "Back Squat")
        XCTAssertEqual(ex.hardSetCount, 3)
        XCTAssertEqual(ex.topSetWeightKg, 100)
        XCTAssertEqual(ex.topSetReps, 5)
        XCTAssertTrue(ex.patterns.contains(.squat))
        XCTAssertTrue(ex.bodyParts.contains(.legs))
        XCTAssertEqual(ex.maxRPE, 9)
        XCTAssertEqual(ex.maxRPE, 9)
    }

    func testCardioWorkoutToTrainingEvent() throws {
        let ctx = try makeContext()
        let cardio = CardioWorkout(type: .run, start: testNow.addingTimeInterval(-3600),
                                    end: testNow.addingTimeInterval(-1800), distance: 5000,
                                    avgHeartRate: 160, source: .iphone)
        ctx.insert(cardio)
        try ctx.save()

        let event = TrainingEvent.from(cardio: cardio)
        XCTAssertEqual(event.source, .appCardio)

        guard case .aerobic(let d) = event.kind else {
            XCTFail("Expected aerobic event"); return
        }
        XCTAssertEqual(d.modality, .running)
        XCTAssertEqual(d.duration, 1800, accuracy: 1)
        XCTAssertEqual(d.intensity, .vigorous)
        XCTAssertEqual(d.intensityConfidence, .moderate)
    }

    func testCardioWorkoutWithoutHRDefaultsToModerateLowConfidence() throws {
        let ctx = try makeContext()
        let cardio = CardioWorkout(type: .walk, start: testNow.addingTimeInterval(-3600),
                                    end: testNow.addingTimeInterval(-1800), source: .iphone)
        ctx.insert(cardio)
        try ctx.save()

        let event = TrainingEvent.from(cardio: cardio)
        guard case .aerobic(let d) = event.kind else { XCTFail("Expected aerobic"); return }
        XCTAssertEqual(d.intensity, .moderate)
        XCTAssertEqual(d.intensityConfidence, .low)
    }

    func testInProgressSessionHasInProgressCompletion() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(date: testNow.addingTimeInterval(-600), in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(
            named: "InProg Squat", primaryMuscles: ["quadriceps"], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 80, reps: 5, in: ctx)

        let event = TrainingEvent.from(session: session)
        XCTAssertEqual(event?.completion, .inProgress)
    }

    func testWarmupSetsNotCountedAsHard() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(date: testNow.addingTimeInterval(-3600), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(
            named: "Bench Press", primaryMuscles: ["chest"], secondaryMuscles: ["triceps"], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 40, reps: 10, isWarmup: true, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 60, reps: 5, isWarmup: true, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 5, rpe: 8, in: ctx)
        session.endedAt = testNow

        let event = TrainingEvent.from(session: session)
        guard case .strength(let details) = event?.kind, let d = details else { XCTFail(); return }
        XCTAssertEqual(d.exercises.first?.hardSetCount, 1)
        XCTAssertEqual(d.totalHardSets, 1)
    }

    func testHardClassification() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(date: testNow.addingTimeInterval(-3600), in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(
            named: "Hard Squat", primaryMuscles: ["quadriceps"], in: ctx)
        for _ in 0..<8 {
            _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 9, in: ctx)
        }
        session.endedAt = testNow

        let event = TrainingEvent.from(session: session)
        XCTAssertTrue(event?.isHard ?? false)
    }

    func testEasyCardioIsNotHard() throws {
        let ctx = try makeContext()
        let cardio = CardioWorkout(type: .walk, start: testNow.addingTimeInterval(-3600),
                                    end: testNow.addingTimeInterval(-1800), avgHeartRate: 100, source: .iphone)
        ctx.insert(cardio)
        try ctx.save()

        let event = TrainingEvent.from(cardio: cardio)
        XCTAssertFalse(event.isHard)
    }
}
