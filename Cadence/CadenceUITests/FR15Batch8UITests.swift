import XCTest

/// Feedback batch 8 — quick-start shortcuts from the Home stat tiles, optional cardio
/// distance goals, the body-parts "fill the gaps" quick start, and the redesigned
/// exercise picker (popular shortlist + body-part filter chips + EXRX links).
final class FR15Batch8UITests: CadenceUITestCase {

    // Steps tile → Run/Walk dialog → distance-goal chooser → outdoor screen w/ goal.
    func testStepsTileStartsRunWithGoal() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.scrollToHittableAndTap("home.stepsTile"), "steps tile")
        XCTAssertTrue(app.buttons["steps.run"].waitTap(), "Start Run")
        XCTAssertTrue(app.buttons["goal.preset.5K"].waitTap(), "5K goal preset")
        XCTAssertTrue(app.otherElements["outdoor.goal"].waitForExistence(timeout: 25)
                      || app.staticTexts["outdoor.elapsed"].waitForExistence(timeout: 10),
                      "the outdoor recorder should open showing the goal")
    }

    // Cardio-min tile → the Start picker filtered to cardio types (no Strength).
    func testCardioTileShowsCardioOnlyPicker() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.scrollToHittableAndTap("home.cardioTile"), "cardio tile")
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

    // Exercise picker: popular-first with EXRX links + body-part filter chips.
    func testExercisePickerPopularFilterAndExrx() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.startEmptyStrengthWorkout(), "session screen")
        app.buttons["session.addExercise"].tap()

        // Popular shortlist shows Bench Press with an EXRX info button + Browse-all.
        XCTAssertTrue(app.buttons["picker.row.Bench Press"].waitForExistence(timeout: 25),
                      "popular shortlist shows Bench Press")
        XCTAssertTrue(app.buttons["picker.exrx.Bench Press"].exists, "EXRX reference link present")

        // Filter to Back → a back movement that isn't in the popular shortlist appears.
        XCTAssertTrue(app.buttons["picker.filter.back"].waitTap(), "Back filter chip")
        XCTAssertTrue(app.buttons["picker.row.Back Extension"].waitForExistence(timeout: 10),
                      "filtering by Back surfaces back exercises")
    }
}
