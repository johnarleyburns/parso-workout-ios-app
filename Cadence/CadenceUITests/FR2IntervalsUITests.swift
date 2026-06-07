import XCTest

/// Field-testing §06 — HIIT & boxing interval engine launched from Start Workout.
final class FR2IntervalsUITests: CadenceUITestCase {

    func testBoxingIntervalViaHome() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.startWorkout"].waitTap(), "Start Workout")
        XCTAssertTrue(app.buttons["startType.boxing"].waitTap(), "Boxing type")

        // Setup sheet → pick the 3 min / 1 min preset.
        XCTAssertTrue(app.buttons["interval.preset.box-3-1"].waitTap(), "boxing preset")

        // Full-screen runner shows the big countdown.
        XCTAssertTrue(app.staticTexts["interval.countdown"].waitForExistence(timeout: 25),
                      "interval countdown should render")
        app.buttons["interval.pause"].tap()
        app.buttons["interval.end"].tap()

        // Back on Home; a boxing workout is now in history.
        XCTAssertTrue(app.buttons["home.startWorkout"].waitForExistence(timeout: 25))
        app.goToTab("Cardio")
        XCTAssertTrue(app.buttons["cardioRow.boxing"].waitForExistence(timeout: 25),
                      "boxing session should be saved to history")
    }

    func testHIITPresetsListed() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.startWorkout"].waitTap())
        XCTAssertTrue(app.buttons["startType.hiit"].waitTap(), "HIIT type")
        XCTAssertTrue(app.buttons["interval.preset.tabata"].waitForExistence(timeout: 15), "Tabata preset")
        XCTAssertTrue(app.buttons["interval.preset.norwegian"].exists, "Norwegian 4×4 preset")
        // Launch Tabata and confirm the runner appears.
        app.buttons["interval.preset.tabata"].tap()
        XCTAssertTrue(app.staticTexts["interval.countdown"].waitForExistence(timeout: 25),
                      "Tabata runner should start")
        app.buttons["interval.end"].tap()
    }
}
