import XCTest

/// UI tests for FR-5 history, PRs & trends. Run on iPhone and iPad.
final class FR5TrendsUITests: CadenceUITestCase {

    // FR-5.1 / 5.2 — per-exercise trend chart + PRs.
    func testExerciseTrendAndPRs() {
        let app = XCUIApplication.launched(seeds: ["history"])
        app.goToTab("Trends")

        XCTAssertTrue(app.staticTexts["Personal Records"].waitForExistence(timeout: 25),
                      "global recent-PRs section should be listed")

        app.buttons["trends.exercise.Bench Press"].waitTap()
        XCTAssertTrue(app.segmentedControls["trend.metric"].waitForExistence(timeout: 25),
                      "metric picker should be present")
        XCTAssertTrue(app.staticTexts["PR Timeline"].waitForExistence(timeout: 15),
                      "per-exercise PR timeline should render")
        // Switch metric to Volume; the chart should remain.
        if app.buttons["Volume"].exists { app.buttons["Volume"].tap() }
        XCTAssertTrue(app.otherElements["trend.chart"].waitForExistence(timeout: 15)
                      || app.staticTexts["History"].exists,
                      "trend content should remain after switching metric")
    }

    // FR-5.4 — consistency heatmap.
    func testConsistencyHeatmap() {
        let app = XCUIApplication.launched(seeds: ["history"])
        app.goToTab("Trends")
        XCTAssertTrue(app.otherElements["trends.consistency"].waitForExistence(timeout: 25)
                      || app.staticTexts["Consistency"].waitForExistence(timeout: 15),
                      "consistency heatmap should render")
    }

    // FR-5.3 — cardio detail with HR overlay.
    func testCardioHRDetail() {
        let app = XCUIApplication.launched()
        app.goToTab("Cardio")
        let row = app.buttons["cardioRow.run"]
        XCTAssertTrue(row.waitForExistence(timeout: 25), "synced run row")
        row.tap()
        XCTAssertTrue(app.otherElements["cardioDetail.hrChart"].waitForExistence(timeout: 25)
                      || app.staticTexts["Heart Rate"].waitForExistence(timeout: 15),
                      "HR chart should render in cardio detail")
    }
}
