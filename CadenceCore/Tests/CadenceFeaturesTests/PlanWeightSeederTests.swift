import Foundation
import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct PlanWeightSeederTests {
    @Test func missingLoadsUseExactRepHistoryThenLastWeight() {
        let history = PartnerPlanResolver.ExerciseHistory(
            lastSets: [.init(weightKg: 80, reps: 8), .init(weightKg: 80, reps: 8)],
            firstWorkingWeightKg: 70)
        let sets = [EditableSet(targetReps: 8, targetWeight: nil),
                    EditableSet(targetReps: 5, targetWeight: nil)]
        let filled = PlanWeightSeeder.fillMissingLoads(sets, history: history)
        #expect(filled[0].targetWeight == 80)
        #expect(filled[1].targetWeight != nil)
    }

    @Test func explicitAndPercentageLoadsAreUntouched() {
        let history = PartnerPlanResolver.ExerciseHistory(lastSets: [.init(weightKg: 100, reps: 5)])
        let explicit = EditableSet(targetReps: 5, targetWeight: 60)
        let percent = EditableSet(targetReps: 5, targetWeight: nil,
                                  loadMode: .percentageOfOneRepMax, oneRepMaxPercent: 80)
        let filled = PlanWeightSeeder.fillMissingLoads([explicit, percent], history: history)
        #expect(filled[0].targetWeight == 60)
        #expect(filled[1].targetWeight == nil)
        #expect(filled[1].loadMode == .percentageOfOneRepMax)
    }

    @Test func emptyHistoryLeavesLoadUnresolvedRatherThanInventingZero() {
        let filled = PlanWeightSeeder.fillMissingLoads(
            [EditableSet(targetReps: 8, targetWeight: nil)],
            history: .empty)
        #expect(filled[0].targetWeight == nil)
    }

    @Test func neverTrainedMovementStaysBlankEvenWhenOtherLiftsHaveHistory() {
        let history = PartnerPlanResolver.ExerciseHistory(generalLastWeightKg: 42)
        let filled = PlanWeightSeeder.fillMissingLoads(
            [EditableSet(targetReps: 10, targetWeight: nil)],
            history: history)
        #expect(filled[0].targetWeight == nil,
                "a movement with no history must not inherit an unrelated lift's load")
    }

    @Test func olderLoadedSetsFillWhenTheLatestSessionHadNoLoad() {
        let history = PartnerPlanResolver.ExerciseHistory(
            lastSets: [.init(weightKg: 0, reps: 8)],
            weightSamples: [
                SetSample(weight: 40, reps: 8, date: Date(timeIntervalSince1970: 10))
            ])
        let filled = PlanWeightSeeder.fillMissingLoads(
            [EditableSet(targetReps: 8, targetWeight: nil)],
            history: history)
        #expect(filled[0].targetWeight == 40)
    }

    @Test func eachExerciseUsesItsOwnHistoryRatherThanOneSharedDefault() {
        let plan = EditablePlan(title: "Plan", warmupMinutes: 0, cooldownMinutes: 0, exercises: [
            EditableExercise(name: "Bench Press",
                             sets: [EditableSet(targetReps: 8, targetWeight: nil)], notes: ""),
            EditableExercise(name: "Back Squat",
                             sets: [EditableSet(targetReps: 8, targetWeight: nil)], notes: ""),
            EditableExercise(name: "Cable Fly",
                             sets: [EditableSet(targetReps: 10, targetWeight: nil)], notes: ""),
        ])
        let history: [String: PartnerPlanResolver.ExerciseHistory] = [
            "Bench Press": .init(lastSets: [.init(weightKg: 60, reps: 8)]),
            "Back Squat": .init(lastSets: [.init(weightKg: 100, reps: 8)]),
        ]
        let filled = PlanWeightSeeder.fill(plan: plan) { name, _ in
            history[name] ?? .init(generalLastWeightKg: 110)
        }
        #expect(filled.exercises[0].sets[0].targetWeight == 60)
        #expect(filled.exercises[1].sets[0].targetWeight == 100)
        #expect(filled.exercises[2].sets[0].targetWeight == nil)
    }
}
