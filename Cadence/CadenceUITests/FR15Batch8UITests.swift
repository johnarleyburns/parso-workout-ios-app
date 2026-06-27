import XCTest

/// Feedback batch 8 — quick-start shortcuts from the Home quick-actions row,
/// optional cardio distance goals, and the redesigned exercise picker (popular
/// shortlist + body-part filter chips + in-app detail).
final class FR15Batch8UITests: CadenceUITestCase {

    // Hero "Start Workout" → opens the Strength start screen directly.
    func testHeroOpensStrengthStart() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.startWorkout"].waitTap(), "Start Workout hero")
        XCTAssertTrue(app.buttons["weights.quickStart"].waitForExistence(timeout: 10),
                      "hero should open the Strength start screen")
    }

    // "Start Cardio" → Run → distance-goal chooser → outdoor screen w/ goal.
    func testStartCardioRunWithGoal() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.startCardio"].waitTap(), "Start Cardio")
        XCTAssertTrue(app.buttons["startType.run"].waitTap(), "Start Run")
        XCTAssertTrue(app.buttons["goal.preset.5K"].waitTap(), "5K goal preset")
        XCTAssertTrue(app.otherElements["outdoor.goal"].waitForExistence(timeout: 25)
                      || app.staticTexts["outdoor.elapsed"].waitForExistence(timeout: 10),
                      "the outdoor recorder should open showing the goal")
    }

    // "Start Cardio" → cardio-only picker (no Strength).
    func testCardioButtonShowsCardioOnlyPicker() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.startCardio"].waitTap(), "Start Cardio")
        XCTAssertTrue(app.buttons["startType.run"].waitForExistence(timeout: 10), "Run offered")
        XCTAssertFalse(app.buttons["startType.weights"].exists, "Strength should be filtered out")
    }

    // Home shows the rest-of-week plan and keeps history behind "View more".
    func testHomeShowsPlanAndWhatYouDidSurfaces() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.descendants(matching: .any)["home.plannedRestOfWeek"].waitForExistence(timeout: 10),
                      "rest-of-week plan card should exist")

        let whatYouDid = app.descendants(matching: .any)["home.whatYouDid"].firstMatch
        for _ in 0..<8 where !whatYouDid.exists {
            app.swipeUp()
        }
        XCTAssertTrue(whatYouDid.exists, "What you did card should exist")
        XCTAssertTrue(app.buttons["home.train"].exists, "History should be behind View more")
    }

    // Tapping "Add" inside ExerciseDetailView should dismiss the picker sheet and
    // return to the session with the exercise planned (NavigationLink replaced with
    // programmatic navigation to avoid row-tap conflict with the picker Button).
    func testDetailViewAddDismissesPickerAndPlansExercise() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.startEmptyStrengthWorkout(), "session screen")
        app.buttons["session.addExercise"].tap()

        XCTAssertTrue(app.buttons["picker.info.Bench Press"].waitTap(), "info button for Bench Press")
        XCTAssertTrue(app.buttons["detail.add"].waitTap(), "Add button in detail view")

        // After tapping Add, the picker sheet must be dismissed and the session
        // must show the planned exercise card for Bench Press.
        XCTAssertFalse(app.buttons["picker.cancel"].waitForExistence(timeout: 2),
                       "picker sheet must be dismissed")
        XCTAssertTrue(app.staticTexts["exerciseCard.Bench Press"].waitForExistence(timeout: 15)
                      || app.buttons["set.add.Bench Press"].waitForExistence(timeout: 10),
                      "session must show the planned Bench Press card")
    }

    // Exercise picker: popular-first with in-app detail (P2) + body-part filter chips.
    func testExercisePickerPopularFilterAndDetail() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.startEmptyStrengthWorkout(), "session screen")
        app.buttons["session.addExercise"].tap()

        // Popular shortlist shows Bench Press with an in-app detail info button.
        XCTAssertTrue(app.buttons["picker.row.Bench Press"].waitForExistence(timeout: 25),
                      "popular shortlist shows Bench Press")
        XCTAssertTrue(app.buttons["picker.info.Bench Press"].exists, "in-app detail button present")

        // Filter to Back → a back movement that isn't in the popular shortlist appears.
        XCTAssertTrue(app.buttons["picker.filter.back"].waitTap(), "Back filter chip")
        XCTAssertTrue(app.buttons["picker.row.Back Extension"].waitForExistence(timeout: 10),
                      "filtering by Back surfaces back exercises")
    }
}
