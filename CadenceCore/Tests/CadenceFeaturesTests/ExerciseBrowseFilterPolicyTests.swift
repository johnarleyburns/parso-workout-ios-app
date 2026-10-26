import XCTest
@testable import CadenceFeatures

final class ExerciseBrowseFilterPolicyTests: XCTestCase {
    func testEquipmentFirstBrowsePreservesEquipmentWhenGroupChanges() {
        XCTAssertFalse(ExerciseBrowseFilterPolicy.resetsEquipmentOnGroupChange(mode: .byEquipment))
    }

    func testMuscleFirstBrowseResetsEquipmentWhenGroupChanges() {
        XCTAssertTrue(ExerciseBrowseFilterPolicy.resetsEquipmentOnGroupChange(mode: .byMuscleGroup))
    }
}
