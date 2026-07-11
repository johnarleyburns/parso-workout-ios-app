import XCTest

/// Feedback batch 4 (field-testing round 4B) — Home plan summary, configurable
/// cardio goal + warm-up/cool-down lengths in Settings, the "Start with Warm-Up"
/// path, the "Cool Down" control on a strength session, and interval
/// (HIIT/boxing) history detail in the summary.
final class FR11Feedback4UITests: CadenceUITestCase {

    // MARK: Home summary

    func testHomeShowsPlanAndWhatYouDidSummary() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.descendants(matching: .any)["home.headerDate"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.descendants(matching: .any)["home.plannedRestOfWeek"].exists)

        let whatYouDid = app.descendants(matching: .any)["home.whatYouDid"].firstMatch
        for _ in 0..<8 where !whatYouDid.exists { app.swipeUp() }
        XCTAssertTrue(whatYouDid.exists, "Home should show the compact training summary")
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
        let app = XCUIApplication.launched(extraArgs: ["-warmupMinutes", "1"])
        XCTAssertTrue(app.tapToReveal("home.startWorkout", "weights.quickStart"), "Start Workout")
        // Enable warm-up in the plan editor before starting
        let warmupStepper = app.steppers["editor.warmup"]
        XCTAssertTrue(warmupStepper.waitForExistence(timeout: 10))
        warmupStepper.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.tapToReveal("editor.start", "warmup.remaining"),
                      "the warm-up timer should appear")
        XCTAssertTrue(app.tapToReveal("warmup.skip", "session.addExercise"),
                      "finishing the warm-up should open the session")
    }

    // The warm-up is pausable (the count freezes while paused).
    func testWarmUpPauses() {
        let app = XCUIApplication.launched(extraArgs: ["-warmupMinutes", "1"])
        XCTAssertTrue(app.tapToReveal("home.startWorkout", "weights.quickStart"), "Start Workout")
        // Enable warm-up in the plan editor before starting
        let warmupStepper = app.steppers["editor.warmup"]
        XCTAssertTrue(warmupStepper.waitForExistence(timeout: 10))
        warmupStepper.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.tapToReveal("editor.start", "warmup.remaining"), "warm-up timer")

        let remaining = app.staticTexts["warmup.remaining"]
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
        XCTAssertTrue(app.pickExercise("Bench Press"), "pick Bench Press")
        app.recordKeypadSet("100")
        app.dismissRestBar()

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
        XCTAssertTrue(app.buttons["home.startCardio"].waitTap(), "Start Cardio")
        XCTAssertTrue(app.buttons["startType.boxing"].waitTap(), "Boxing type")
        XCTAssertTrue(app.buttons["interval.start"].waitTap(), "START")
        XCTAssertTrue(app.staticTexts["interval.countdown"].waitForExistence(timeout: 25),
                      "interval runner")
        app.buttons["interval.end"].tap()
        XCTAssertTrue(app.dialogButton("workout.endConfirm").waitTap(), "confirm End")

        XCTAssertTrue(app.staticTexts["summary.interval.protocol"].waitForExistence(timeout: 25),
                      "the interval summary should list the protocol")
        XCTAssertTrue(app.staticTexts["summary.interval.rounds"].exists,
                      "the interval summary should show completed rounds")
        XCTAssertTrue(app.buttons["summary.done"].waitTap(), "Done")
    }

    // MARK: — unified plan cool-down / end confirmation (2026-06-22)

    func testEndConfirmationHasCoolDownOption() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.startEmptyStrengthWorkout(), "session screen")

        // Log a set so the session has content
        XCTAssertTrue(app.pickExercise("Bench Press"), "pick Bench Press")
        app.recordKeypadSet("80")

        // End — should confirm with three options
        if app.buttons["workout.end"].exists {
            app.buttons["workout.end"].tap()
        } else {
            app.buttons["workout.end"].firstMatch.tap()
        }
        XCTAssertTrue(app.dialogButton("workout.endCoolDown").waitForExistence(timeout: 10),
                      "End confirmation should show 'Cool down, then finish'")
        XCTAssertTrue(app.dialogButton("workout.endConfirm").exists,
                      "End confirmation should show 'End'")
        XCTAssertTrue(app.dialogButton("workout.endCancel").exists,
                      "End confirmation should show 'Keep going'")
        // Dismiss
        app.dialogButton("workout.endCancel").tap()
    }
}
