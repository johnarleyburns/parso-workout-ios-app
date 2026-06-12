import XCTest

/// Field-testing Round 4 Part A — workout lifecycle (A1 universal Pause/Resume +
/// End, A2 "Are you sure?" confirm). Phases 4A-3/4A-4 extend this file with the
/// always-on summary and unified-history tests.
final class FR7LifecycleUITests: CadenceUITestCase {

    // Helper: start a new empty strength workout via Train and land on the session.
    private func startStrength(_ app: XCUIApplication) {
        app.goToTab("Train")
        XCTAssertTrue(app.buttons["train.newWorkout"].waitTap(), "New Workout button")
        XCTAssertTrue(app.buttons["session.addExercise"].waitForExistence(timeout: 25), "session screen")
    }

    // Helper: log one Bench Press set so the session is non-empty.
    private func logBenchSet(_ app: XCUIApplication, weight: String = "100") {
        app.buttons["session.addExercise"].tap()
        XCTAssertTrue(app.buttons["picker.row.Bench Press"].waitTap(), "picker row Bench Press")
        let weightField = app.textFields["set.weight"]
        XCTAssertTrue(weightField.waitForExistence(timeout: 25), "set editor")
        weightField.tap()
        weightField.typeText(weight)
        app.buttons["set.save"].tap()
        // A rest timer may auto-start; skip it so the 1 Hz animation doesn't stall
        // the accessibility tree on a slow simulator.
        if app.buttons["rest.skip"].waitForExistence(timeout: 3) { app.buttons["rest.skip"].tap() }
    }

    // A1 — the pre-workout countdown can be paused (freezes the count) and resumed,
    // and Skip still starts the workout.
    func testCountdownPause() {
        let app = XCUIApplication.launched(extraArgs: ["-preCountdown", "30"])
        XCTAssertTrue(app.buttons["home.startWorkout"].waitTap(), "Start Workout")
        XCTAssertTrue(app.buttons["startType.weights"].waitTap(), "Weights type")

        let remaining = app.staticTexts["countdown.remaining"]
        XCTAssertTrue(remaining.waitForExistence(timeout: 25), "countdown should render")

        // Pause freezes the count.
        XCTAssertTrue(app.buttons["countdown.pause"].waitTap(), "Pause")
        let frozen = remaining.label
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertEqual(remaining.label, frozen, "count should not advance while paused")

        // Resume, then Skip → the session opens.
        XCTAssertTrue(app.buttons["countdown.pause"].waitTap(), "Resume")
        XCTAssertTrue(app.buttons["countdown.skip"].waitTap(), "Skip")
        XCTAssertTrue(app.buttons["session.addExercise"].waitForExistence(timeout: 25),
                      "skipping the countdown should open the session")
    }

    // A1/A2 — strength Pause/Resume, and End routes through an "Are you sure?"
    // confirm (Keep going cancels; confirming leaves the session).
    func testStrengthPauseAndConfirmEnd() {
        let app = XCUIApplication.launched()
        startStrength(app)
        logBenchSet(app)

        // Pause flips the label to Resume; tap again to resume.
        let pause = app.buttons["workout.pause"]
        XCTAssertTrue(pause.waitTap(), "Pause")
        XCTAssertTrue(pause.label.localizedCaseInsensitiveContains("Resume"),
                      "pause button should read Resume while paused")
        XCTAssertTrue(pause.waitTap(), "Resume")

        // End → confirm dialog. Keep going cancels (still on the session).
        XCTAssertTrue(app.buttons["workout.end"].waitTap(), "End")
        XCTAssertTrue(app.buttons["workout.endCancel"].waitTap(), "Keep going cancels")
        XCTAssertTrue(app.buttons["session.addExercise"].waitForExistence(timeout: 10),
                      "cancelling End keeps us on the session")

        // End again → confirm → finishes & saves, leaving the session. (Started
        // from Train, so we pop back to Train — the saved workout now lists there.)
        XCTAssertTrue(app.buttons["workout.end"].waitTap(), "End again")
        XCTAssertTrue(app.buttons["workout.endConfirm"].waitTap(), "confirm End")
        XCTAssertTrue(app.buttons["train.newWorkout"].waitForExistence(timeout: 25),
                      "confirming End finishes the workout and leaves the session")
        XCTAssertFalse(app.buttons["session.addExercise"].exists,
                       "the live session screen should be gone after End")
        XCTAssertTrue(app.buttons["session.row"].firstMatch.waitForExistence(timeout: 10),
                      "the finished workout should be saved to history")
    }
}
