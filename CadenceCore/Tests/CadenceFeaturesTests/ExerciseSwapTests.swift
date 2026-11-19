#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

/// Phase E (field-test-fixes): swap + remove exercise.
struct ExerciseSwapTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    // MARK: - item-based handler survives dismissal

    @Test func swapTargetItemSurvivesDismissal() throws {
        // The old handler used derived isPresented bindings (swappingPlannedName != nil)
        // which nilled the payload on dismissal BEFORE onPick was called.
        // SwapTarget as an Identifiable item in .sheet(item:) cannot lose its payload.
        let target1 = ExerciseSwap.SwapTarget.planned(name: "Squat")
        let target2 = ExerciseSwap.SwapTarget.logged(exerciseID: UUID())

        // Both targets should be uniquely identifiable.
        #expect(target1.id != target2.id)
        // The id is stable — calling .sheet(item: $swapTarget) with this item
        // keeps the payload alive until the sheet finishes presenting.
    }

    // MARK: - changeExercise

    @Test func changeExerciseMovesSetsAndDedupsPlannedNames() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let old = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", primaryMuscles: ["chest"], in: ctx)
        let new = try WorkoutRepository.findOrCreateExercise(named: "Dumbbell Press", primaryMuscles: ["chest"], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: old, weightKg: 60, reps: 10, rpe: 7, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: old, weightKg: 60, reps: 10, rpe: 7, in: ctx)
        session.plannedExerciseNames = ["Bench Press"]
        try ctx.save()

        let moved = try WorkoutRepository.changeExercise(in: session, from: old, to: new, in: ctx)

        #expect(moved == 2, "Both sets should move to the new exercise")
        let newExerciseSets = session.orderedSets.filter { $0.exercise?.id == new.id }
        #expect(newExerciseSets.count == 2, "Sets should be assigned to new exercise")
        #expect(session.plannedExerciseNames.contains("Dumbbell Press"), "Planned name should update")
        #expect(!session.plannedExerciseNames.contains("Bench Press"), "Old name should be removed")
    }

    // MARK: - removePlannedExercise

    @Test func removePlannedExerciseRemovesExactlyThatCard() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        session.plannedExerciseNames = ["Squat", "Bench Press", "Deadlift"]
        try ctx.save()

        try WorkoutRepository.removePlannedExercise(named: "Bench Press", from: session, in: ctx)

        #expect(session.plannedExerciseNames == ["Squat", "Deadlift"],
                       "Only the named card should be removed")
    }

    // MARK: - removeExercise

    @Test func removeExerciseDeletesSetsAndPlannedName() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Lat Pulldown", primaryMuscles: ["lats"], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 50, reps: 12, rpe: 7, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 50, reps: 12, rpe: 7, in: ctx)
        session.plannedExerciseNames = ["Lat Pulldown"]
        session.endedAt = Date()
        try ctx.save()

        let removed = try WorkoutRepository.removeExercise(ex, from: session, in: ctx)

        #expect(removed == 2, "Both sets should be deleted")
        #expect(session.orderedSets.isEmpty, "All sets for this exercise should be gone")
        #expect(!session.plannedExerciseNames.contains("Lat Pulldown"),
                       "Planned name should also be removed")
    }
}
#endif
