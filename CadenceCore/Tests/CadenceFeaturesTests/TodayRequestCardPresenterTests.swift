import XCTest
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

final class TodayRequestCardPresenterTests: XCTestCase {
    func testIdleStateShowsRequestButtonTappable() {
        let d = TodayRequestCardPresenter.make(title: "Suggest a strength workout", state: .idle, resultSummary: nil)
        XCTAssertFalse(d.isLoading)
        XCTAssertTrue(d.isTappable)
        XCTAssertEqual(d.buttonLabel, "Suggest a strength workout")
        XCTAssertEqual(d.accessibilityLabel, "Suggest a strength workout")
    }

    func testRequestingStateIsLoadingAndNotTappable() {
        let d = TodayRequestCardPresenter.make(title: "Suggest a strength workout", state: .requesting, resultSummary: nil)
        XCTAssertTrue(d.isLoading)
        XCTAssertFalse(d.isTappable)
        XCTAssertTrue(d.accessibilityLabel.contains("Suggest a strength workout"))
    }

    func testResultStateShowsSummaryAndIsTappableToReopen() {
        let d = TodayRequestCardPresenter.make(title: "Suggest a strength workout", state: .result,
                                               resultSummary: "Upper Body Hypertrophy · 45 min")
        XCTAssertEqual(d.title, "Upper Body Hypertrophy · 45 min")
        XCTAssertTrue(d.isTappable)
        XCTAssertFalse(d.isLoading)
    }

    func testResultStateFallsBackToOriginalTitleIfSummaryMissing() {
        let d = TodayRequestCardPresenter.make(title: "Suggest cardio", state: .result, resultSummary: nil)
        XCTAssertEqual(d.title, "Suggest cardio")
    }

    func testFailedStateShowsTryAgainAndSurfacesMessageInAccessibilityLabel() {
        let d = TodayRequestCardPresenter.make(title: "Suggest cardio", state: .failed("No history yet"),
                                               resultSummary: nil)
        XCTAssertEqual(d.buttonLabel, "Try again")
        XCTAssertTrue(d.isTappable)
        XCTAssertTrue(d.accessibilityLabel.contains("No history yet"))
    }
}
