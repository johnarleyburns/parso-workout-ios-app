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

final class PlanningSelectionPolicyTests: XCTestCase {
    func testPlanningAddsAndStaysWhilePickersDismiss() {
        XCTAssertEqual(ExerciseSelectionPolicy.outcome(isPlanning: true), .addToDraftAndStay)
        XCTAssertEqual(ExerciseSelectionPolicy.outcome(isPlanning: false), .completeAndDismiss)
    }

    func testSummaryTexts() {
        XCTAssertEqual(PlanningDraftSummary.headline(nil), PlanningDraftSummary.emptyMessage)
        let s = PlanningDraftSummary(id: UUID(), title: "Push", exerciseCount: 2)
        XCTAssertEqual(PlanningDraftSummary.headline(s), "Push")
        XCTAssertEqual(PlanningDraftSummary.countText(1), "1 exercise")
        XCTAssertEqual(PlanningDraftSummary.countText(2), "2 exercises")
    }
}
