import XCTest

/// UI tests for FR-3 daily activity launch behavior. Home now prioritizes the
/// coach recommendation, rest-of-week plan, and compact training summary.
final class FR3StepsUITests: CadenceUITestCase {

    func testHomeHeaderAndPlanLoadWithActivityData() {
        let app = XCUIApplication.launched(extraArgs: ["-todaySteps", "8200"])
        XCTAssertTrue(app.descendants(matching: .any)["home.headerDate"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.descendants(matching: .any)["home.plannedRestOfWeek"].exists)
    }

    func testHomeWhatYouDidSummaryExists() {
        let app = XCUIApplication.launched()
        let summary = app.descendants(matching: .any)["home.whatYouDid"].firstMatch
        for _ in 0..<8 where !summary.exists { app.swipeUp() }
        XCTAssertTrue(summary.exists, "Home should show the compact training summary")
    }
}
