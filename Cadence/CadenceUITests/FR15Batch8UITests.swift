import XCTest

/// Feedback batch 8 — quick-start shortcuts from the Home stat tiles, optional cardio
/// distance goals, the body-parts "fill the gaps" quick start, and the redesigned
/// exercise picker (popular shortlist + body-part filter chips + in-app detail).
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

    // Volume tile → strength start (Quick Start available).
    func testVolumeTileShowsStrengthStart() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.scrollToHittableAndTap("home.volumeTile"), "volume tile")
        XCTAssertTrue(app.buttons["weights.quickStart"].waitForExistence(timeout: 10),
                      "strength Quick Start should be offered")
    }

    // Body-parts tile → the fill-the-gaps quick start (build from suggestions).
    func testBodyPartsTileOpensFillTheGaps() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.scrollToHittableAndTap("home.bodyPartsTile"), "body-parts tile")
        XCTAssertTrue(app.staticTexts["bodyQuick.missing"].waitForExistence(timeout: 10),
                      "the fill-the-gaps sheet should list the missing parts")
        XCTAssertTrue(app.buttons["bodyQuick.buildStart"].waitForExistence(timeout: 5),
                      "with no past workouts it should offer building from suggestions")
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
