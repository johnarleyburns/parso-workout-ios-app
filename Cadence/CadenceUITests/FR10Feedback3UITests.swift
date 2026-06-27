import XCTest

/// Feedback batch 3 (field-testing round 4B) — Home plan/history surfaces, the
/// "Strength" library with fixed (5×5/Olympic) and flexible presets
/// (rep-scheme chooser), first-class bodyweight sets, and partner-aware history.
final class FR10Feedback3UITests: CadenceUITestCase {

    // MARK: Home dashboard

    // Home now surfaces the rest-of-week plan and the compact training summary.
    func testHomeShowsPlanAndTrainingSummary() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.descendants(matching: .any)["home.plannedRestOfWeek"].waitForExistence(timeout: 25),
                      "Home should show the rest-of-week plan")
        XCTAssertTrue(app.buttons["home.yourPlan"].exists, "Home should link to Your Plan")
        let summary = app.descendants(matching: .any)["home.whatYouDid"].firstMatch
        for _ in 0..<8 where !summary.exists { app.swipeUp() }
        XCTAssertTrue(summary.exists, "Home should show the compact training summary")
    }

    // MARK: Strength library

    private func openStrengthLibrary(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["home.startWorkout"].waitTap(), "Start Workout")
        XCTAssertTrue(app.buttons["weights.quickStart"].waitForExistence(timeout: 25),
                      "Strength start screen")
    }

    // A fixed program (5×5 Week 1A) launches straight into a planned session — no
    // rep-scheme prompt — pre-loaded with its prescribed movements.
    func testStrengthLibraryFixedFiveByFive() {
        let app = XCUIApplication.launched()
        openStrengthLibrary(app)
        XCTAssertTrue(app.scrollToAndTapButton("weights.library.preset-5x5-1a"),
                      "5×5 Week 1A library row")
        XCTAssertTrue(app.buttons["editor.start"].waitTap(), "Start the preset")
        XCTAssertTrue(app.staticTexts["session.rx.Back Squat"].waitForExistence(timeout: 25),
                      "the 5×5 session should be planned with Back Squat + its Rx")
    }

    // A flexible split (Push) prompts for a set/rep scheme; choosing "3 sets ·
    // 12-10-8" applies that ladder to every movement in the launched session.
    func testStrengthLibraryFlexiblePresetWithRepScheme() {
        let app = XCUIApplication.launched()
        openStrengthLibrary(app)
        XCTAssertTrue(app.scrollToAndTapButton("weights.library.preset-push"),
                      "Push library row")
        // The rep-scheme chooser appears (flexible template, feedback batch 3).
        XCTAssertTrue(app.buttons["repScheme.3x"].waitTap(), "3 sets · 12-10-8")
        XCTAssertTrue(app.buttons["editor.start"].waitTap(), "Start with the ladder")
        let rx = app.staticTexts["session.rx.Bench Press"]
        XCTAssertTrue(rx.waitForExistence(timeout: 25),
                      "the planned session should carry the chosen scheme")
        XCTAssertTrue(rx.label.contains("12"),
                      "the 12-10-8 ladder should be reflected in the prescription")
    }

    // The custom per-set rep editor builds a ladder one set at a time, then starts.
    func testStrengthLibraryCustomRepScheme() {
        let app = XCUIApplication.launched()
        openStrengthLibrary(app)
        XCTAssertTrue(app.scrollToAndTapButton("weights.library.preset-pull"),
                      "Pull library row")
        XCTAssertTrue(app.buttons["repScheme.custom"].waitTap(), "Custom…")
        XCTAssertTrue(app.buttons["customRep.add"].waitForExistence(timeout: 10),
                      "the per-set editor should appear")
        app.buttons["customRep.add"].tap() // grow to 4 sets
        XCTAssertTrue(app.buttons["customRep.continue"].waitTap(), "Preview the custom sets")
        XCTAssertTrue(app.buttons["editor.start"].waitTap(), "Start the custom scheme")
        XCTAssertTrue(app.staticTexts["session.rx.Deadlift"].waitForExistence(timeout: 25),
                      "the custom-scheme session should be planned with Deadlift")
    }

    // MARK: Bodyweight sets

    // Logging a bodyweight movement (Pull-Up) defaults to a BW set; the row shows
    // "BW" rather than a 0 kg weight.
    func testBodyweightSetShowsBW() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.startEmptyStrengthWorkout(), "session screen")

        app.buttons["session.addExercise"].tap()
        // Pull-Up sits below the fold in the grouped picker; search to surface it.
        let search = app.searchFields["picker.search"].exists
            ? app.searchFields["picker.search"] : app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 25), "exercise search field")
        search.tap(); search.typeText("Pull-Up")
        XCTAssertTrue(app.buttons["picker.row.Pull-Up"].waitTap(), "pick Pull-Up")

        // A bodyweight exercise shows the Bodyweight toggle, defaulted on.
        let bwToggle = app.switches["set.bodyweight"]
        XCTAssertTrue(bwToggle.waitForExistence(timeout: 25), "Bodyweight toggle should show")
        let reps = app.textFields["set.reps"]
        if reps.exists { reps.tap(); reps.clearAndType("8") }
        app.buttons["set.save"].tap()
        if app.buttons["rest.skip"].waitForExistence(timeout: 3) { app.buttons["rest.skip"].tap() }

        let bwRow = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "BW")).firstMatch
        XCTAssertTrue(bwRow.waitForExistence(timeout: 25),
                      "a pure bodyweight set should render as \"BW × reps\"")
    }

    // MARK: Partner-aware session + summary

    // With a partner in the session, the owner's own sets are tagged "Me", and the
    // end-of-workout summary lists the partner's exercises in their own section.
    func testMeChipAndPartnerSummary() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.startEmptyStrengthWorkout(), "session screen")

        // Add partner Sam.
        XCTAssertTrue(app.buttons["partner.add"].waitTap(), "add partner")
        let nameField = app.alerts.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "partner name field")
        nameField.typeText("Sam")
        app.alerts.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["partner.chip.Sam"].waitForExistence(timeout: 10),
                      "Sam in the partner bar")

        // Log one set for me (Bench Press).
        app.buttons["session.addExercise"].tap()
        XCTAssertTrue(app.buttons["picker.row.Bench Press"].waitTap(), "pick Bench Press")
        app.recordKeypadSet("100")
        if app.buttons["rest.skip"].waitForExistence(timeout: 3) { app.buttons["rest.skip"].tap() }

        // The owner's set is tagged "Me" once a partner is present.
        XCTAssertTrue(app.staticTexts["set.performer.Me"].waitForExistence(timeout: 25),
                      "owner sets should be tagged Me with a partner present")

        // Log one set for Sam (same exercise card, via the performer picker).
        app.buttons["set.add.Bench Press"].firstMatch.tap()
        app.keypadEnter("80")
        let picker = app.buttons["set.performedBy"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.tap()
        XCTAssertTrue(app.buttons["Sam"].waitTap(), "select Sam")
        app.buttons["set.save"].tap()
        if app.buttons["rest.skip"].waitForExistence(timeout: 3) { app.buttons["rest.skip"].tap() }
        XCTAssertTrue(app.staticTexts["set.performer.Sam"].waitForExistence(timeout: 25),
                      "Sam's set should carry her tag")

        // End → confirm → the summary shows a Partners section for Sam.
        XCTAssertTrue(app.buttons["workout.end"].waitTap(), "End")
        XCTAssertTrue(app.buttons["workout.endConfirm"].waitTap(), "confirm End")
        XCTAssertTrue(app.staticTexts["summary.partner.Sam"].waitForExistence(timeout: 25),
                      "the summary should surface the partner's section")
        XCTAssertTrue(app.buttons["summary.done"].waitTap(), "Done")
    }
}
