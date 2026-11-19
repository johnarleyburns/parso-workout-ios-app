import Foundation
import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct WorkoutPlanRepStructureTests {
    @Test func applyingPartnerStructurePreservesOwnerAndOtherPartnerLoads() {
        let partner = UUID()
        let other = UUID()
        let sets = [EditableSet(targetReps: 8, targetWeight: 25)]
        var plan = EditablePlan(warmupMinutes: 0, cooldownMinutes: 0, exercises: ["Squat", "Row"].map {
            EditableExercise(name: $0, sets: sets, notes: "", performerPlans: [
                .init(performerID: nil, name: "Me", sets: sets),
                .init(performerID: partner, name: "Pat", sets: sets),
                .init(performerID: other, name: "Sam", sets: sets)
            ])
        })
        plan.applyRepStructure([12, 10, 8], performerID: partner)
        for exercise in plan.exercises {
            #expect(exercise.sets == sets)
            #expect(exercise.performerPlans[0].sets == sets)
            #expect(exercise.performerPlans[1].sets.map(\.targetReps) == [12, 10, 8])
            #expect(exercise.performerPlans[1].sets.map(\.targetWeight) == [25, 25, 25])
            #expect(exercise.performerPlans[2].sets == sets)
        }
        #expect(plan.performerPrescriptions().first { $0.performerID == partner.uuidString }?
            .exercises.map { $0.sets.map(\.targetReps) } == [[12, 10, 8], [12, 10, 8]])
        plan.applyRepStructure([5, 5], performerID: nil)
        #expect(plan.exercises.allSatisfy { $0.sets.map(\.targetReps) == [5, 5] && $0.performerPlans[0].sets == $0.sets })
    }

    @Test func mountainClimbersAreBodyweightWithoutAnExternalLoad() {
        let exercise = Exercise(name: "Mountain Climbers")
        #expect(SessionViewModel.isNonWeighted(exercise))
        let entry = SessionViewModel.normalizedSetEntry(exercise: exercise, requestedWeightKg: 20, requestedUsesBodyweight: false)
        #expect(entry.weightKg == 0)
        #expect(entry.usesBodyweight)
    }
}
