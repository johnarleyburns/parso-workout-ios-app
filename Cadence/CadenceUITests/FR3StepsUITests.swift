import XCTest

/// UI tests for FR-3 daily activity & steps. Field-test round 3 surfaces these
/// directly on Home; feedback batch 4 renders the steps tile as a "value / goal"
/// ratio with a progress bar, alongside the cardio-minutes tile.
final class FR3StepsUITests: CadenceUITestCase {

    // FR-3.1 / 3.3 — step count (as value / goal) + the cardio-minutes tile on Home.
    func testStepsAndWeekCount() {
        let app = XCUIApplication.launched(extraArgs: ["-todaySteps", "8200"])
        // Activity lives on Home now; the steps tile reads "8,200 / 10,000".
        let steps = app.staticTexts["today.steps"]
        XCTAssertTrue(steps.waitForExistence(timeout: 25))
        expectation(for: NSPredicate(format: "label BEGINSWITH %@", "8,200"), evaluatedWith: steps)
        waitForExpectations(timeout: 20)

        XCTAssertTrue(app.staticTexts["home.cardioMinutes"].exists, "cardio-minutes tile")
    }

    // FR-3.2 — the steps tile shows progress toward the daily goal.
    func testStepCountAndTrend() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.staticTexts["today.steps"].waitForExistence(timeout: 25),
                      "simple step count should be visible on Home")
        XCTAssertTrue(app.progressIndicators["today.steps.progress"].waitForExistence(timeout: 25),
                      "the steps tile should show goal progress")
    }
}
