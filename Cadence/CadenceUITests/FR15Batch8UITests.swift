import XCTest

/// Feedback batch 8 — quick-start shortcuts from the Home quick-actions row and
/// stat tiles, optional cardio distance goals, and the redesigned exercise picker
/// (popular shortlist + body-part filter chips + in-app detail).
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

    // "This week" card shows the four key metrics and missing body parts.
    func testThisWeekCardShowsMetrics() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.descendants(matching: .any)["home.thisWeek"].waitForExistence(timeout: 10),
                      "This week card should exist")
        XCTAssertTrue(app.descendants(matching: .any)["home.workoutsCount"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["home.cardioMinutes"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["home.volume"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["home.bodyParts"].exists)
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
