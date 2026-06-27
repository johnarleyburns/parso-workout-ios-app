import XCTest

/// Feedback batch 6 item 3 — "Log Workout" (manual entry that lands in history just
/// like a live one, flagged "Logged") and "Other Cardio" (free-text description +
/// GPS-or-not). Items 1/2 (inline keypad) are covered by FR1/FR8/FR10.
final class FR13Feedback6UITests: CadenceUITestCase {

    // Logging a run lands it in History with the "Logged" tag.
    func testLogCardioAppearsAsLogged() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.logWorkout"].waitTap(), "Log Workout")
        XCTAssertTrue(app.buttons["logType.run"].waitTap(), "Run log tile")
        XCTAssertTrue(app.buttons["log.save"].waitTap(), "Log Workout save")

        XCTAssertTrue(app.scrollToHittableAndTap("home.train"), "open History")
        XCTAssertTrue(app.buttons["history.cardioRow.run"].waitForExistence(timeout: 25),
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

        XCTAssertTrue(app.scrollToHittableAndTap("home.train"), "open History")
        XCTAssertTrue(app.staticTexts["Rowing"].waitForExistence(timeout: 25),
                      "the custom description should show as the workout title")
    }

    // Batch 7 follow-up — manually logging a STRENGTH workout: Log Workout →
    // Strength → Add Exercises → log a set → Done lands it in history "Logged".
    func testLogStrengthAppearsAsLogged() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.logWorkout"].waitTap(), "Log Workout")
        XCTAssertTrue(app.buttons["logType.strength"].waitTap(), "Strength log tile")
        XCTAssertTrue(app.buttons["log.addExercises"].waitTap(), "Add Exercises")

        XCTAssertTrue(app.buttons["session.addExercise"].waitForExistence(timeout: 25),
                      "manual-log session screen")
        app.buttons["session.addExercise"].tap()
        XCTAssertTrue(app.buttons["picker.row.Bench Press"].waitTap(), "Bench Press row")
        app.recordKeypadSet("100")

        XCTAssertTrue(app.buttons["log.done"].waitTap(), "Done")
        XCTAssertTrue(app.scrollToHittableAndTap("home.train"), "open History")
        XCTAssertTrue(app.buttons["session.row"].waitForExistence(timeout: 25),
                      "the logged strength workout should appear in history")
        XCTAssertTrue(app.staticTexts["workout.loggedTag"].waitForExistence(timeout: 10)
                      || app.images["workout.loggedTag"].waitForExistence(timeout: 2),
                      "a logged workout should carry the Logged tag")
    }

    // Choosing Other Cardio from Start opens a description + GPS entry first.
    func testOtherCardioLiveEntryHasDescriptionAndGPS() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.startCardio"].waitTap(), "Start Cardio")
        XCTAssertTrue(app.buttons["startType.other"].waitTap(), "Other type")

        XCTAssertTrue(app.textFields["otherCardio.desc"].waitForExistence(timeout: 10),
                      "Other Cardio description field")
        XCTAssertTrue(app.switches["otherCardio.gps"].waitForExistence(timeout: 5),
                      "Other Cardio GPS toggle")
    }
}
