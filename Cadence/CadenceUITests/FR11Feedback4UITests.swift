import XCTest

/// Feedback batch 4 (field-testing round 4B) — Home goal ratios (steps + cardio
/// minutes shown as value/goal with a progress bar), configurable cardio goal +
/// warm-up/cool-down lengths in Settings, the "Start with Warm-Up" path, the
/// "Cool Down" control on a strength session, and interval (HIIT/boxing) history
/// detail in the summary.
final class FR11Feedback4UITests: CadenceUITestCase {

    // MARK: Home goal ratios

    // The steps and cardio tiles show progress toward a goal: a "value / goal"
    // label and a progress bar.
    func testHomeTilesShowGoalRatios() {
        let app = XCUIApplication.launched()
        let steps = app.staticTexts["today.steps"]
        XCTAssertTrue(steps.waitForExistence(timeout: 25), "steps tile should show")
        XCTAssertTrue(steps.label.contains("/"), "steps should read as value / goal")
        let cardio = app.staticTexts["home.cardioMinutes"]
        XCTAssertTrue(cardio.waitForExistence(timeout: 10), "cardio tile should show")
        XCTAssertTrue(cardio.label.contains("/"), "cardio minutes should read as value / goal")
        XCTAssertTrue(app.progressIndicators["today.steps.progress"].waitForExistence(timeout: 10),
                      "steps tile should show a progress bar")
        XCTAssertTrue(app.progressIndicators["home.cardioMinutes.progress"].exists,
                      "cardio tile should show a progress bar")
    }

    // MARK: Settings — goal + warm-up/cool-down

    func testSettingsHasGoalAndWarmupSteppers() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.scrollToHittableAndTap("home.settings"), "open Settings")
        // The new rows are appended at the bottom of the Form; scroll until each
        // stepper is on screen.
        for id in ["settings.cardioGoal", "settings.warmupMinutes", "settings.cooldownMinutes"] {
            let stepper = app.steppers[id]
            var found = stepper.waitForExistence(timeout: 3)
            var swipes = 0
            while !found && swipes < 8 { app.swipeUp(); found = stepper.exists; swipes += 1 }
            XCTAssertTrue(found, "Settings should expose the \(id) stepper")
        }
    }

    // MARK: Start with Warm-Up

    // Choosing "Start with Warm-Up" shows a guided warm-up timer; Skip opens the
    // blank session.
    func testStartWithWarmUpThenSession() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.startWorkout"].waitTap(), "Start Workout")
        XCTAssertTrue(app.buttons["startType.weights"].waitTap(), "Strength type")
        XCTAssertTrue(app.buttons["weights.warmupStart"].waitTap(), "Start with Warm-Up")

        XCTAssertTrue(app.staticTexts["warmup.remaining"].waitForExistence(timeout: 25),
                      "the warm-up timer should appear")
        XCTAssertTrue(app.buttons["warmup.skip"].waitTap(), "Skip the warm-up")
        XCTAssertTrue(app.buttons["session.addExercise"].waitForExistence(timeout: 25),
                      "finishing the warm-up should open the session")
    }

    // The warm-up is pausable (the count freezes while paused).
    func testWarmUpPauses() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.startWorkout"].waitTap(), "Start Workout")
        XCTAssertTrue(app.buttons["startType.weights"].waitTap(), "Strength type")
        XCTAssertTrue(app.buttons["weights.warmupStart"].waitTap(), "Start with Warm-Up")

        let remaining = app.staticTexts["warmup.remaining"]
        XCTAssertTrue(remaining.waitForExistence(timeout: 25), "warm-up timer")
        XCTAssertTrue(app.buttons["warmup.pause"].waitTap(), "Pause")
        let frozen = remaining.label
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertEqual(remaining.label, frozen, "count should not advance while paused")
    }

    // MARK: Cool Down

    // A strength session offers a Cool Down action that runs a timer and, on Skip,
    // finishes the workout (the summary appears).
    func testCoolDownFinishesWorkout() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.startEmptyStrengthWorkout(), "session screen")

        // Log a Bench set so the summary has content.
        app.buttons["session.addExercise"].tap()
        XCTAssertTrue(app.buttons["picker.row.Bench Press"].waitTap(), "pick Bench Press")
        app.recordKeypadSet("100")
        if app.buttons["rest.skip"].waitForExistence(timeout: 3) { app.buttons["rest.skip"].tap() }

        XCTAssertTrue(app.scrollToAndTapButton("workout.coolDown"), "Cool Down")
        // Cool Down now confirms first (batch 7 item 6) so an accidental tap can't
        // end the workout.
        XCTAssertTrue(app.buttons["workout.coolDownConfirm"].waitTap(), "confirm Cool Down")
        XCTAssertTrue(app.staticTexts["cooldown.remaining"].waitForExistence(timeout: 25),
                      "the cool-down timer should appear")
        XCTAssertTrue(app.buttons["cooldown.skip"].waitTap(), "Skip the cool-down")
        XCTAssertTrue(app.staticTexts["summary.exercise.Bench Press"].waitForExistence(timeout: 25),
                      "finishing the cool-down should end the workout and show the summary")
        XCTAssertTrue(app.buttons["summary.done"].waitTap(), "Done")
    }

    // MARK: Interval history detail

    // Ending a boxing interval shows the protocol structure in the summary.
    func testBoxingSummaryShowsIntervalDetail() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.startWorkout"].waitTap(), "Start Workout")
        XCTAssertTrue(app.buttons["startType.boxing"].waitTap(), "Boxing type")
        XCTAssertTrue(app.buttons["interval.start"].waitTap(), "START")
        // Pre-workout HR gate (feedback batch 5) — continue without HR.
        XCTAssertTrue(app.buttons["prehr.skip"].waitTap(), "Continue without HR")
        XCTAssertTrue(app.staticTexts["interval.countdown"].waitForExistence(timeout: 25),
                      "interval runner")
        app.buttons["interval.end"].tap()
        XCTAssertTrue(app.buttons["workout.endConfirm"].waitTap(), "confirm End")

        XCTAssertTrue(app.staticTexts["summary.interval.protocol"].waitForExistence(timeout: 25),
                      "the interval summary should list the protocol")
        XCTAssertTrue(app.staticTexts["summary.interval.rounds"].exists,
                      "the interval summary should show completed rounds")
        XCTAssertTrue(app.buttons["summary.done"].waitTap(), "Done")
    }
}
