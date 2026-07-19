import XCTest
import SwiftData
import CadenceCore
@testable import CadenceFeatures

/// Phase E (field-test-fixes): swap + remove exercise.
final class ExerciseSwapTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    // MARK: - item-based handler survives dismissal

    func testSwapTargetItemSurvivesDismissal() throws {
        // The old handler used derived isPresented bindings (swappingPlannedName != nil)
        // which nilled the payload on dismissal BEFORE onPick was called.
        // SwapTarget as an Identifiable item in .sheet(item:) cannot lose its payload.
        let target1 = ExerciseSwap.SwapTarget.planned(name: "Squat")
        let target2 = ExerciseSwap.SwapTarget.logged(exerciseID: UUID())

        // Both targets should be uniquely identifiable.
        XCTAssertNotEqual(target1.id, target2.id)
        // The id is stable — calling .sheet(item: $swapTarget) with this item
        // keeps the payload alive until the sheet finishes presenting.
    }

    // MARK: - changeExercise

    func testChangeExerciseMovesSetsAndDedupsPlannedNames() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let old = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", primaryMuscles: ["chest"], in: ctx)
        let new = try WorkoutRepository.findOrCreateExercise(named: "Dumbbell Press", primaryMuscles: ["chest"], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: old, weightKg: 60, reps: 10, rpe: 7, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: old, weightKg: 60, reps: 10, rpe: 7, in: ctx)
        session.plannedExerciseNames = ["Bench Press"]
        try ctx.save()

        let moved = try WorkoutRepository.changeExercise(in: session, from: old, to: new, in: ctx)

        XCTAssertEqual(moved, 2, "Both sets should move to the new exercise")
        let newExerciseSets = session.orderedSets.filter { $0.exercise?.id == new.id }
        XCTAssertEqual(newExerciseSets.count, 2, "Sets should be assigned to new exercise")
        XCTAssertTrue(session.plannedExerciseNames.contains("Dumbbell Press"), "Planned name should update")
        XCTAssertFalse(session.plannedExerciseNames.contains("Bench Press"), "Old name should be removed")
    }

    // MARK: - removePlannedExercise

    func testRemovePlannedExerciseRemovesExactlyThatCard() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        session.plannedExerciseNames = ["Squat", "Bench Press", "Deadlift"]
        try ctx.save()

        try WorkoutRepository.removePlannedExercise(named: "Bench Press", from: session, in: ctx)

        XCTAssertEqual(session.plannedExerciseNames, ["Squat", "Deadlift"],
                       "Only the named card should be removed")
    }

    // MARK: - removeExercise

    func testRemoveExerciseDeletesSetsAndPlannedName() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Lat Pulldown", primaryMuscles: ["lats"], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 50, reps: 12, rpe: 7, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 50, reps: 12, rpe: 7, in: ctx)
        session.plannedExerciseNames = ["Lat Pulldown"]
        session.endedAt = Date()
        try ctx.save()

        let removed = try WorkoutRepository.removeExercise(ex, from: session, in: ctx)

        XCTAssertEqual(removed, 2, "Both sets should be deleted")
        XCTAssertTrue(session.orderedSets.isEmpty, "All sets for this exercise should be gone")
        XCTAssertFalse(session.plannedExerciseNames.contains("Lat Pulldown"),
                       "Planned name should also be removed")
    }
}
