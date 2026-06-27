import XCTest

/// Feedback batch 7 — field-test polish. Item 5 (log a 0 kg set), item 3 (type
/// cardio minutes directly), item 6 (cool-down confirmation guard), and items 8/9
/// (Settings toggles for idle auto-end + workout sounds). The styling items (1/4),
/// the get-ready/Quick-Start change, and the haptics/bells (2/9) are visual/audio
/// and verified on-device; here we cover the behavioral surfaces.
final class FR14Feedback7UITests: CadenceUITestCase {

    // Item 5 — an empty-bar 0 kg set is recordable and saves to the workout.
    func testLogZeroKgSet() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.startEmptyStrengthWorkout(), "session screen")
        app.buttons["session.addExercise"].tap()
        XCTAssertTrue(app.buttons["picker.row.Bench Press"].waitTap(), "Bench Press")

        app.keypadEnter("0", clear: true)
        XCTAssertTrue(app.buttons["set.save"].isEnabled, "0 kg should be recordable (item 5)")
        app.buttons["set.save"].tap()
        if app.buttons["rest.skip"].waitForExistence(timeout: 3) { app.buttons["rest.skip"].tap() }

        // End → the summary lists Bench Press, proving the 0 kg set was saved.
        XCTAssertTrue(app.buttons["workout.end"].waitTap(), "End")
        XCTAssertTrue(app.buttons["workout.endConfirm"].waitTap(), "confirm End")
        XCTAssertTrue(app.staticTexts["summary.exercise.Bench Press"].waitForExistence(timeout: 25),
                      "the 0 kg set is saved to the workout")
    }

    // Item 3 — cardio minutes can be typed directly (not only via the stepper).
    func testLogCardioMinutesTypedDirectly() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.logWorkout"].waitTap(), "Log Workout")
        XCTAssertTrue(app.buttons["logType.run"].waitTap(), "Run log tile")

        let mins = app.textFields["log.minutes"]
        XCTAssertTrue(mins.waitForExistence(timeout: 10), "minutes is a typable field")
        mins.clearAndType("42")
        XCTAssertTrue(app.buttons["log.save"].waitTap(), "Log Workout save")

        let lastCardio = app.descendants(matching: .any)["home.fact.lastCardio"].firstMatch
        for _ in 0..<8 where !lastCardio.exists { app.swipeUp() }
        XCTAssertTrue(lastCardio.exists,
                      "the logged run appears in Home's latest cardio fact")
    }

    // Item 6 — Cool Down asks "are you sure?" first; Cancel keeps the session.
    func testCoolDownAsksConfirmation() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.startEmptyStrengthWorkout(), "session screen")

        XCTAssertTrue(app.buttons["workout.coolDown"].waitTap(), "Cool Down")
        XCTAssertTrue(app.buttons["workout.coolDownConfirm"].waitForExistence(timeout: 5),
                      "cool-down shows a confirmation guard (item 6)")
        // Dismiss the dialog (Cancel) and confirm we're still on the session.
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        XCTAssertTrue(app.buttons["session.addExercise"].waitForExistence(timeout: 10),
                      "cancelling keeps us on the session")
    }

    // Items 8 & 9 — Settings exposes the idle auto-end and workout-sounds toggles.
    func testSettingsHasIdleAndSoundToggles() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.scrollToHittableAndTap("home.settings"), "open Settings")

        XCTAssertTrue(app.scrollToSwitch("settings.autoEndOnIdle"),
                      "Auto-end-when-idle toggle exists (item 8)")
        XCTAssertTrue(app.scrollToSwitch("settings.workoutSounds"),
                      "Workout-sounds toggle exists (item 9)")
    }
}

private extension XCUIApplication {
    /// Swipes up until a switch with `id` is on screen.
    func scrollToSwitch(_ id: String, maxSwipes: Int = 10) -> Bool {
        let sw = switches[id]
        if sw.waitForExistence(timeout: 4), sw.isHittable { return true }
        for _ in 0..<maxSwipes {
            swipeUp()
            if sw.exists && sw.isHittable { return true }
        }
        return sw.exists
    }
}
