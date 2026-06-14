import XCTest

/// Feedback batch 6 item 3 — "Log Workout" (manual entry that lands in history just
/// like a live one, flagged "Logged") and "Other Cardio" (free-text description +
/// GPS-or-not). Items 1/2 (inline keypad) are covered by FR1/FR8/FR10.
final class FR13Feedback6UITests: CadenceUITestCase {

    // Logging a run lands it in Home's recent workouts with the "Logged" tag.
    func testLogCardioAppearsAsLogged() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.logWorkout"].waitTap(), "Log Workout")
        XCTAssertTrue(app.buttons["logType.run"].waitTap(), "Run log tile")
        XCTAssertTrue(app.buttons["log.save"].waitTap(), "Log Workout save")

        XCTAssertTrue(app.buttons["home.cardioRow.run"].waitForExistence(timeout: 25),
                      "the logged run should appear in history")
        XCTAssertTrue(app.staticTexts["workout.loggedTag"].waitForExistence(timeout: 10)
                      || app.images["workout.loggedTag"].waitForExistence(timeout: 2),
                      "a logged workout should carry the Logged tag")
    }

    // Other Cardio logging uses the free-text description as the history title.
    func testLogOtherCardioUsesDescription() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.logWorkout"].waitTap(), "Log Workout")
        XCTAssertTrue(app.buttons["logType.other"].waitTap(), "Other Cardio log tile")

        let desc = app.textFields["log.desc"]
        XCTAssertTrue(desc.waitForExistence(timeout: 10), "description field")
        desc.tap(); desc.typeText("Rowing")
        XCTAssertTrue(app.buttons["log.save"].waitTap(), "Log Workout save")

        XCTAssertTrue(app.staticTexts["Rowing"].waitForExistence(timeout: 25),
                      "the custom description should show as the workout title")
    }

    // Choosing Other Cardio from Start opens a description + GPS entry first.
    func testOtherCardioLiveEntryHasDescriptionAndGPS() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.startWorkout"].waitTap(), "Start Workout")
        XCTAssertTrue(app.buttons["startType.other"].waitTap(), "Other type")

        XCTAssertTrue(app.textFields["otherCardio.desc"].waitForExistence(timeout: 10),
                      "Other Cardio description field")
        XCTAssertTrue(app.switches["otherCardio.gps"].waitForExistence(timeout: 5),
                      "Other Cardio GPS toggle")
    }
}
