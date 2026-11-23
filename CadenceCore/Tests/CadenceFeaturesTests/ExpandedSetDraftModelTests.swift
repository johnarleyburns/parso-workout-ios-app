import Testing
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore

struct ExpandedSetDraftModelTests {
    @Test func onlyExplicitRepEntryMarksRepsEdited() {
        var draft = ExpandedSetDraftModel(weight: 20, reps: 6, rpe: nil, unit: .kilograms)
        #expect(!draft.didEditReps)
        draft.adjustWeight(by: 5)
        #expect(!draft.didEditReps)
        draft.setReps(10)
        #expect(draft.didEditReps)
        var stepped = ExpandedSetDraftModel(weight: 20, reps: 6, rpe: nil, unit: .kilograms)
        stepped.adjustReps(by: 1)
        #expect(stepped.didEditReps)
    }
    @Test func allIncrementsAdjustExactlyAndClamp() {
        for unit in MeasurementUnitPreference.allCases {
            for increment in ExpandedSetDraftModel.increments(for: unit) {
                var model = ExpandedSetDraftModel(weight: 10, reps: 5, rpe: nil, unit: unit)
                model.adjustWeight(by: increment)
                #expect(abs(model.weight - (10 + increment)) <= 0.0001)
                model.adjustWeight(by: -Double.infinity)
                #expect(model.weight == 0)
                model.setWeight(ExpandedSetDraftModel.maxWeight)
                model.adjustWeight(by: increment)
                #expect(model.weight == ExpandedSetDraftModel.maxWeight)
            }
        }
    }

    @Test func quarterWeightSurvivesUnrelatedMutationsAndConvertsOnce() {
        var model = ExpandedSetDraftModel(weight: 225.25, reps: 5, rpe: nil, unit: .pounds)
        let kg = model.canonicalWeightKg
        model.adjustReps(by: 1)
        model.selectEffort(8)
        #expect(abs(model.weight - 225.25) <= 0.0001)
        #expect(abs(model.canonicalWeightKg - kg) <= 0.0000001)
    }

    @Test func repBoundsAndModes() {
        var model = ExpandedSetDraftModel(weight: 0, reps: 1, rpe: nil, unit: .kilograms)
        model.adjustReps(by: -1)
        #expect(model.reps == 1)
        model.adjustReps(by: 1000)
        #expect(model.reps == 100)
        model.selectEffort(2)
        model.selectMode(.rir)
        #expect(model.effort == 8)
        #expect(WatchEffortMode.rir.rpeValue(from: model.effort) == 2)
        model.selectEffort(nil)
        #expect(model.effort == nil)
    }

    @Test func effortStepperStartsAtSevenAndClearsAtMinimum() {
        var model = ExpandedSetDraftModel(weight: 0, reps: 5, rpe: nil, unit: .kilograms)
        #expect(model.effort == nil)
        model.adjustEffort(by: 1)
        #expect(model.effort == 7)
        var lowered = ExpandedSetDraftModel(weight: 0, reps: 5, rpe: nil, unit: .kilograms)
        lowered.adjustEffort(by: -1)
        #expect(lowered.effort == nil)
        model.adjustEffort(by: 1)
        #expect(model.effort == 8)
        model.adjustEffort(by: -1)
        #expect(model.effort == 7)
        model.adjustEffort(by: -1)
        #expect(model.effort == 6)
        model.adjustEffort(by: -1)
        #expect(model.effort == 5)
        model.adjustEffort(by: -1)
        #expect(model.effort == 4)
        model.adjustEffort(by: -1)
        #expect(model.effort == 3)
        model.adjustEffort(by: -1)
        #expect(model.effort == 2)
        model.adjustEffort(by: -1)
        #expect(model.effort == 1)
        model.adjustEffort(by: -1)
        #expect(model.effort == nil)
        model.adjustEffort(by: -1)
        #expect(model.effort == nil, "a second minus at none is a no-op")
        model.selectEffort(9)
        model.adjustEffort(by: 100)
        #expect(model.effort == 10)
    }

    @Test func submitIsIdempotentAndNoneIsValid() {
        var model = ExpandedSetDraftModel(weight: 0, reps: 5, rpe: nil, unit: .kilograms)
        #expect(model.submit() != nil)
        #expect(model.submit() == nil)
    }

    @Test func untouchedDirectWeightIsBlankButExplicitZeroIsVisible() {
        #expect(ExpandedSetDraftModel.displayWeightText(
            0, hasExplicitEntry: false, bodyweight: false) == "")
        #expect(ExpandedSetDraftModel.displayWeightText(
            0, hasExplicitEntry: true, bodyweight: false) == "0")
        #expect(ExpandedSetDraftModel.displayWeightText(
            0, hasExplicitEntry: false, bodyweight: true) == "0")
    }
}
