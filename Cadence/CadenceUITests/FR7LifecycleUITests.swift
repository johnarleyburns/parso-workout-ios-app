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

    // P2 (#7) — the strength/CrossFit session shows a prominent elapsed clock that
    // advances while training and freezes the instant the workout is paused.
    func testSessionElapsedTimerRunsAndFreezesOnPause() {
        let app = XCUIApplication.launched()
        startStrength(app)
        logBenchSet(app)

        let elapsed = app.staticTexts["session.elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 25), "elapsed timer should show")

        // It advances while the workout is active.
        let running = elapsed.label
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertNotEqual(elapsed.label, running, "timer should advance while training")

        // Pause freezes the display (the clock excludes paused time).
        XCTAssertTrue(app.buttons["workout.pause"].waitTap(), "Pause")
        let frozen = elapsed.label
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertEqual(elapsed.label, frozen, "timer should freeze while paused")
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

        // End again → confirm → the summary appears (A3); Done finishes & saves,
        // leaving the session. (Started from Train, so we pop back to Train — the
        // saved workout now lists there.)
        XCTAssertTrue(app.buttons["workout.end"].waitTap(), "End again")
        XCTAssertTrue(app.buttons["workout.endConfirm"].waitTap(), "confirm End")
        XCTAssertTrue(app.buttons["summary.done"].waitTap(), "summary Done")
        XCTAssertTrue(app.buttons["train.newWorkout"].waitForExistence(timeout: 25),
                      "confirming End finishes the workout and leaves the session")
        XCTAssertFalse(app.buttons["session.addExercise"].exists,
                       "the live session screen should be gone after End")
        XCTAssertTrue(app.buttons["session.row"].firstMatch.waitForExistence(timeout: 10),
                      "the finished workout should be saved to history")
    }

    // A3 — confirming End on a strength workout shows an always-on summary with the
    // exercise roll-up + total volume; Done returns to where it was started.
    func testStrengthEndShowsSummary() {
        let app = XCUIApplication.launched()
        startStrength(app)
        logBenchSet(app, weight: "100")

        XCTAssertTrue(app.buttons["workout.end"].waitTap(), "End")
        XCTAssertTrue(app.buttons["workout.endConfirm"].waitTap(), "confirm End")

        XCTAssertTrue(app.staticTexts["summary.exercise.Bench Press"].waitForExistence(timeout: 25),
                      "summary should list the logged exercise")
        XCTAssertTrue(app.staticTexts["summary.metric.volume"].exists,
                      "summary should show total volume")
        XCTAssertTrue(app.staticTexts["summary.duration"].exists, "summary should show duration")

        XCTAssertTrue(app.buttons["summary.done"].waitTap(), "Done")
        XCTAssertTrue(app.buttons["train.newWorkout"].waitForExistence(timeout: 25),
                      "Done leaves the summary and the finished session")
    }

    // A3 — an indoor cardio recording shows a summary (duration + Done) after End.
    func testCardioEndShowsSummary() {
        let app = XCUIApplication.launched()
        app.goToTab("Cardio")
        XCTAssertTrue(app.buttons["cardio.record"].waitTap(), "Record")
        XCTAssertTrue(app.buttons["record.start.boxing"].waitTap(), "boxing")

        XCTAssertTrue(app.staticTexts["record.elapsed"].waitForExistence(timeout: 25), "recording")
        XCTAssertTrue(app.buttons["record.end"].waitTap(), "End")
        XCTAssertTrue(app.buttons["workout.endConfirm"].waitTap(), "confirm End")

        XCTAssertTrue(app.staticTexts["summary.duration"].waitForExistence(timeout: 25),
                      "cardio summary should show duration")
        XCTAssertTrue(app.buttons["summary.done"].waitTap(), "Done")
        XCTAssertTrue(app.buttons["cardioRow.boxing"].waitForExistence(timeout: 25),
                      "the recorded session should be saved to history")
    }

    // A4 — the unified history lists strength sessions and cardio workouts together.
    func testUnifiedHistoryShowsCardioAndStrength() {
        let app = XCUIApplication.launched(seeds: ["historyMixed"])
        app.goToTab("Train") // Home "Recent workouts → See all" → unified HistoryView

        XCTAssertTrue(app.buttons["session.row"].firstMatch.waitForExistence(timeout: 25),
                      "strength sessions should list")
        XCTAssertTrue(app.buttons["history.cardioRow.walk"].firstMatch.waitForExistence(timeout: 25),
                      "the seeded walk should appear in the same list as strength")
    }

    // A5 — a history row opens the read-only summary (not the editor); a strength
    // summary offers Edit, which opens the set editor.
    func testHistoryRowOpensSummary() {
        let app = XCUIApplication.launched(seeds: ["historyMixed"])
        app.goToTab("Train")

        // Cardio row → summary (duration), no Edit affordance.
        let walk = app.buttons["history.cardioRow.walk"].firstMatch
        XCTAssertTrue(walk.waitForExistence(timeout: 25), "walk row")
        walk.tap()
        XCTAssertTrue(app.staticTexts["summary.duration"].waitForExistence(timeout: 25),
                      "the cardio row opens its summary")
        XCTAssertFalse(app.buttons["summary.edit"].exists, "cardio summary has no Edit")
        app.navigationBars.buttons.element(boundBy: 0).tap() // Back to history

        // Strength row → summary with exercises + Edit → set editor.
        let strength = app.buttons["session.row"].firstMatch
        XCTAssertTrue(strength.waitForExistence(timeout: 25), "strength row")
        strength.tap()
        XCTAssertTrue(app.staticTexts["summary.exercise.Bench Press"].waitForExistence(timeout: 25),
                      "the strength row opens its summary")
        XCTAssertTrue(app.buttons["summary.edit"].waitForExistence(timeout: 5),
                      "strength summary offers Edit")
        app.buttons["summary.edit"].tap()
        XCTAssertTrue(app.buttons["session.addExercise"].waitForExistence(timeout: 25),
                      "Edit opens the set editor for that session")
    }
}
