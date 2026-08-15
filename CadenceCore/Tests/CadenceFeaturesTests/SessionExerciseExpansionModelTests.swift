import XCTest
@testable import CadenceFeatures

final class SessionExerciseExpansionModelTests: XCTestCase {
    func testInitialAndToggle() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(SessionExerciseExpansionModel.initial(exerciseIDs: [a, b], unfinishedIDs: [b], mode: .active), b)
        XCTAssertNil(SessionExerciseExpansionModel.initial(exerciseIDs: [a], unfinishedIDs: [], mode: .active))
        XCTAssertNil(SessionExerciseExpansionModel.initial(exerciseIDs: [a], unfinishedIDs: [a], mode: .review))
        XCTAssertNil(SessionExerciseExpansionModel.headerTapped(current: a, tapped: a))
        XCTAssertEqual(SessionExerciseExpansionModel.headerTapped(current: a, tapped: b), b)
    }

    func testSaveTransitions() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(SessionExerciseExpansionModel.afterSave(current: a, savedExerciseID: a, nextUnfinishedID: b, kind: .pending), a)
        XCTAssertEqual(SessionExerciseExpansionModel.afterSave(current: a, savedExerciseID: a, nextUnfinishedID: b, kind: .unplanned), a)
        XCTAssertEqual(SessionExerciseExpansionModel.afterSave(current: a, savedExerciseID: a, nextUnfinishedID: b, kind: .finalPlanned), b)
    }
}
