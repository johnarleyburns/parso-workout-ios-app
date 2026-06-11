import XCTest

/// UI tests for FR-3 daily activity & steps. Field-test round 3 surfaces these
/// directly on Home (simple step count + workouts-this-week + 7-day trend).
final class FR3StepsUITests: CadenceUITestCase {

    // FR-3.1 / 3.3 — step count + workouts-this-week on Home.
    func testStepsAndWeekCount() {
        let app = XCUIApplication.launched(extraArgs: ["-todaySteps", "8200"])
        // Activity lives on Home now.
        let steps = app.staticTexts["today.steps"]
        XCTAssertTrue(steps.waitForExistence(timeout: 25))
        expectation(for: NSPredicate(format: "label == %@", "8,200"), evaluatedWith: steps)
        waitForExpectations(timeout: 20)

        XCTAssertTrue(app.staticTexts["home.weekCount"].exists, "workouts-this-week tile")
    }

    // FR-3.2 — 7-day trend chart, surfaced on Home.
    func testStepCountAndTrend() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.staticTexts["today.steps"].waitForExistence(timeout: 25),
                      "simple step count should be visible on Home")
        XCTAssertTrue(app.otherElements["today.trendChart"].waitForExistence(timeout: 25)
                      || app.staticTexts["Trends"].exists,
                      "7-day trend should be on Home")
    }
}
