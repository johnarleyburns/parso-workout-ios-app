#if canImport(SwiftData)
import Testing
import Foundation
import SwiftData
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WorkoutEntryPreferenceTests {
    @Test func watchOverrideBeatsLaterPlanSetsAndExercises() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        let model = WatchStrengthFlowModel(context: context, unit: .kilograms,
                                            cooldownDefault: 0, restDefault: 0)
        let names = ["Biceps Curl", "Dumbbell Press"]
        let payload = WatchPlanPayload(strength: .init(exerciseNames: names,
            prescriptions: names.map { name in
                PlannedExercisePrescription(exerciseName: name, sets: [
                    PlannedSetPrescription(targetReps: 6, targetWeightKg: 20),
                    PlannedSetPrescription(targetReps: 6, targetWeightKg: 20)
                ])
            }))
        model.start(title: "Sticky", plannedExerciseNames: names,
                    planPayload: payload, createSession: true)
        let first = try #require(model.exerciseList.first?.exercise)
        model.startLogSet(for: first)
        model.currentReps = 10
        model.currentWeight = 25
        _ = model.logSet()
        model.startLogSet(for: first)
        #expect(model.currentReps == 10)
        #expect(model.currentWeight == 25)
        let second = try #require(model.exerciseList.first { $0.exercise.id != first.id }?.exercise)
        model.startLogSet(for: second)
        #expect(model.currentReps == 10)
        #expect(model.currentWeight == 20)
    }

    @Test func explicitRepsStayWithinWorkoutAndPerformer() {
        let workout = WorkoutSession(title: "Workout")
        let partner = UUID()
        #expect(WorkoutEntryPreference.reps(in: workout, performerID: nil) == nil)
        WorkoutEntryPreference.setReps(10, in: workout, performerID: nil)
        #expect(WorkoutEntryPreference.reps(in: workout, performerID: nil) == 10)
        #expect(WorkoutEntryPreference.reps(in: workout, performerID: partner) == nil)
        WorkoutEntryPreference.setReps(12, in: workout, performerID: partner)
        #expect(WorkoutEntryPreference.reps(in: workout, performerID: nil) == 10)
        #expect(WorkoutEntryPreference.reps(in: workout, performerID: partner) == 12)
        #expect(WorkoutEntryPreference.reps(in: WorkoutSession(title: "Next"), performerID: nil) == nil)
    }
}
#endif
