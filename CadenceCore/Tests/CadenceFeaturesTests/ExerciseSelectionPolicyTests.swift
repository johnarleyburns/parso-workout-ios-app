import XCTest
@testable import CadenceFeatures

final class ExerciseSelectionPolicyTests: XCTestCase {
    func testBrowseModeNearMatchNavigatesAndDoesNotDismiss() {
        XCTAssertEqual(ExerciseSelectionPolicy.outcome(isBrowse: true), .openDetail)
        XCTAssertEqual(ExerciseSelectionPolicy.nearMatchTitle(isBrowse: true), "View exercise")
        XCTAssertFalse(ExerciseSelectionPolicy.showsCancel(isBrowse: true))
    }

    func testBrowseModeCustomExercisePersistsThenShowsDetail() {
        XCTAssertEqual(ExerciseSelectionPolicy.outcome(isBrowse: true), .openDetail)
    }

    func testPickerModeNearMatchCompletesAndDismisses() {
        XCTAssertEqual(ExerciseSelectionPolicy.outcome(isBrowse: false), .completeAndDismiss)
        XCTAssertEqual(ExerciseSelectionPolicy.nearMatchTitle(isBrowse: false), "Use this exercise")
        XCTAssertTrue(ExerciseSelectionPolicy.showsCancel(isBrowse: false))
    }

    func testPickerModeCustomExerciseCompletesAndDismisses() {
        XCTAssertEqual(ExerciseSelectionPolicy.outcome(isBrowse: false), .completeAndDismiss)
    }
}
