import XCTest

/// UI tests for FR-3 daily activity & steps. Run on iPhone and iPad.
final class FR3StepsUITests: CadenceUITestCase {

    // FR-3.1 / 3.3 — step count + activity tiles from HealthKit (faked).
    func testStepsAndActivityTiles() {
        let app = XCUIApplication.launched(extraArgs: ["-todaySteps", "8200"])
        app.goToTab("Today")

        let steps = app.staticTexts["today.steps"]
        XCTAssertTrue(steps.waitForExistence(timeout: 25))
        // Wait for the async load to populate the seeded value.
        expectation(for: NSPredicate(format: "label == %@", "8,200"), evaluatedWith: steps)
        waitForExpectations(timeout: 20)

        XCTAssertTrue(app.staticTexts["today.flights"].exists, "flights tile")
        XCTAssertTrue(app.staticTexts["today.distance"].exists, "distance tile")
        XCTAssertTrue(app.staticTexts["today.energy"].exists, "energy tile")
    }

    // FR-3.2 — goal ring + 7-day trend chart.
    func testGoalRingAndTrend() {
        let app = XCUIApplication.launched()
        app.goToTab("Today")
        XCTAssertTrue(app.otherElements["today.goalRing"].waitForExistence(timeout: 25),
                      "step goal ring should be visible")
        XCTAssertTrue(app.otherElements["today.trendChart"].waitForExistence(timeout: 25)
                      || app.staticTexts["Last 7 Days"].exists,
                      "7-day trend chart should be visible")
    }
}
