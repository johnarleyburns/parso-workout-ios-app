import XCTest
@testable import CadenceFeatures
import CadenceCore

final class ExpandedSetDraftModelTests: XCTestCase {
    func testAllIncrementsAdjustExactlyAndClamp() {
        for unit in MeasurementUnitPreference.allCases {
            for increment in ExpandedSetDraftModel.increments(for: unit) {
                var model = ExpandedSetDraftModel(weight: 10, reps: 5, rpe: nil, unit: unit)
                model.adjustWeight(by: increment)
                XCTAssertEqual(model.weight, 10 + increment, accuracy: 0.0001)
                model.adjustWeight(by: -Double.infinity)
                XCTAssertEqual(model.weight, 0)
                model.setWeight(ExpandedSetDraftModel.maxWeight)
                model.adjustWeight(by: increment)
                XCTAssertEqual(model.weight, ExpandedSetDraftModel.maxWeight)
            }
        }
    }

    func testQuarterWeightSurvivesUnrelatedMutationsAndConvertsOnce() {
        var model = ExpandedSetDraftModel(weight: 225.25, reps: 5, rpe: nil, unit: .pounds)
        let kg = model.canonicalWeightKg
        model.adjustReps(by: 1)
        model.selectEffort(8)
        XCTAssertEqual(model.weight, 225.25, accuracy: 0.0001)
        XCTAssertEqual(model.canonicalWeightKg, kg, accuracy: 0.0000001)
    }

    func testRepBoundsAndModes() {
        var model = ExpandedSetDraftModel(weight: 0, reps: 1, rpe: nil, unit: .kilograms)
        model.adjustReps(by: -1)
        XCTAssertEqual(model.reps, 1)
        model.adjustReps(by: 1000)
        XCTAssertEqual(model.reps, 100)
        model.selectEffort(2)
        model.selectMode(.rir)
        XCTAssertEqual(model.effort, 8)
        XCTAssertEqual(WatchEffortMode.rir.rpeValue(from: model.effort), 2)
        model.selectEffort(nil)
        XCTAssertNil(model.effort)
    }

    func testSubmitIsIdempotentAndNoneIsValid() {
        var model = ExpandedSetDraftModel(weight: 0, reps: 5, rpe: nil, unit: .kilograms)
        XCTAssertNotNil(model.submit())
        XCTAssertNil(model.submit())
    }
}
