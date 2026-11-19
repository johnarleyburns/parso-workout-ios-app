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

    @Test func suggestedOwnerSetsFillMissingStraightLoadsWithoutChangingRepsOrExplicitLoads() {
        let original = (0..<3).map { _ in EditableSet(targetReps: 6, targetWeight: nil) }
        let history = PartnerPlanResolver.ExerciseHistory(lastSets: [
            .init(weightKg: 100, reps: 6),
            .init(weightKg: 92.98643585, reps: 8)
        ])
        let seeded = PartnerPlanResolver.suggestedOwnerSets(original, history: history)
        #expect(seeded.map(\.id) == original.map(\.id))
        #expect(seeded.map(\.targetReps) == [6, 6, 6])
        #expect(seeded.map(\.targetWeight) == [92.98643585, 92.98643585, 92.98643585])
        #expect(PartnerPlanResolver.suggestedOwnerSets(original, history: .empty) == original)

        let firstOnly = PartnerPlanResolver.ExerciseHistory(firstWorkingWeightKg: 50)
        #expect(PartnerPlanResolver.suggestedOwnerSets(original, history: firstOnly)
            .map(\.targetWeight) == [50, 50, 50])

        let bodyweight = [EditableSet(targetReps: 12, targetWeight: nil, loadMode: .bodyweight)]
        #expect(PartnerPlanResolver.suggestedOwnerSets(bodyweight, history: history) == bodyweight)

        let explicit = [EditableSet(targetReps: 12, targetWeight: 20)]
        #expect(PartnerPlanResolver.suggestedOwnerSets(explicit, history: history) == explicit)
    }

    @Test func repSchemeOptionsAreSortedBySetCountThenFirstSetReps() {
        let common = WorkoutPlanRepSchemeOptions.common
        #expect(common.contains([20, 20, 20]), "20-20-20 must be offered as a default option")
        let keys = common.map { "\($0.count)-\($0.first ?? 0)" }
        let sortedKeys = common
            .sorted { $0.count != $1.count ? $0.count < $1.count : ($0.first ?? 0) < ($1.first ?? 0) }
            .map { "\($0.count)-\($0.first ?? 0)" }
        #expect(keys == sortedKeys)
    }

    @Test func repSchemeSummaryFormatsNameAndReps() {
        #expect(WorkoutPlanRepSchemeOptions.summary(name: "Me", reps: [8, 8, 8]) == "Me: 8-8-8")
        #expect(WorkoutPlanRepSchemeOptions.summary(name: "Pat", reps: [12, 10, 8]) == "Pat: 12-10-8")
        #expect(WorkoutPlanRepSchemeOptions.summary(name: "Me", reps: []) == "Me")
    }

    @Test func mountainClimbersAreBodyweightWithoutAnExternalLoad() {
        let exercise = Exercise(name: "Mountain Climbers")
        #expect(SessionViewModel.isNonWeighted(exercise))
        let entry = SessionViewModel.normalizedSetEntry(exercise: exercise, requestedWeightKg: 20, requestedUsesBodyweight: false)
        #expect(entry.weightKg == 0)
        #expect(entry.usesBodyweight)
    }
}
