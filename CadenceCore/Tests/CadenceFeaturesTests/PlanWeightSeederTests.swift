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

    @Test func generalLastWeightIsUsedAsAnEducatedGuessWhenTheMovementIsNew() {
        let history = PartnerPlanResolver.ExerciseHistory(generalLastWeightKg: 42)
        let filled = PlanWeightSeeder.fillMissingLoads(
            [EditableSet(targetReps: 10, targetWeight: nil)],
            history: history)
        #expect(filled[0].targetWeight == 42)
    }
}
