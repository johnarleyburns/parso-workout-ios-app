import XCTest

/// Critical-path tests for the exercise picker (add exercise during a workout).
/// This flow regressed to "extremely slow/jerky search" and "tapping a result
/// does nothing". These lock in that: search filters, a result row opens the
/// detail on the FIRST tap (even with the keyboard up), and Add plans the
/// exercise back on the session.
final class ExercisePickerUITests: CadenceUITestCase {

    private func openPicker() -> XCUIApplication {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.startEmptyStrengthWorkout(), "session screen")
        app.buttons["session.addExercise"].tap()
        XCTAssertTrue(app.buttons["picker.row.Bench Press"].waitForExistence(timeout: 25),
                      "picker should open on the popular shortlist")
        return app
    }

    /// The core "tap does nothing" regression: one tap on a row must open detail.
    func testRowTapOpensDetailOnFirstTap() {
        let app = openPicker()
        app.buttons["picker.row.Bench Press"].tap()
        XCTAssertTrue(app.buttons["detail.add"].waitForExistence(timeout: 10),
                      "tapping a row must open the exercise detail (with Add) on the first tap")
    }

    /// Search → tap a result row → detail opens (the exact user-reported flow).
    func testSearchThenTapResultOpensDetail() {
        let app = openPicker()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "search field")
        field.tap()
        field.typeText("squat")

        let row = app.buttons["picker.row.Back Squat"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "search results should surface Back Squat")
        row.tap()
        XCTAssertTrue(app.buttons["detail.add"].waitForExistence(timeout: 10),
                      "tapping a search result must open detail on the first tap")
    }

    /// Full flow: search → tap result → Add → picker dismisses → session has it.
    func testSearchAddPlansExerciseOnSession() {
        let app = openPicker()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "search field")
        field.tap()
        field.typeText("deadlift")

        let row = app.buttons["picker.row.Deadlift"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "search should surface Deadlift")
        row.tap()

        XCTAssertTrue(app.buttons["detail.add"].waitTap(), "Add in detail")
        XCTAssertFalse(app.buttons["picker.cancel"].waitForExistence(timeout: 2),
                       "picker must dismiss after Add")
        XCTAssertTrue(app.staticTexts["exerciseCard.Deadlift"].waitForExistence(timeout: 15)
                      || app.buttons["set.add.Deadlift"].waitForExistence(timeout: 10),
                      "session must show the added Deadlift")
    }

    /// Selecting a body part reveals a second "equipment" chip row that narrows the
    /// (often hundreds-long) list to a single equipment type (the user's request:
    /// fast browsing when constructing a workout).
    func testEquipmentSubFilterNarrowsBodyPartList() {
        let app = openPicker()

        // Enter the browse-by-body-part flow (the case the user hit: a part has
        // hundreds of movements).
        let chest = app.buttons["picker.filter.chest"]
        XCTAssertTrue(chest.waitForExistence(timeout: 10), "chest body-part chip")
        chest.tap()

        // A second-level equipment chip row appears with the equipment chest offers.
        XCTAssertTrue(app.buttons["picker.equip.dumbbell"].waitForExistence(timeout: 15),
                      "equipment sub-filter should offer Dumbbell for Chest")
        XCTAssertTrue(app.buttons["picker.equip.barbell"].waitForExistence(timeout: 5),
                      "equipment sub-filter should offer Barbell for Chest")

        // Narrow to Dumbbell → dumbbell movements remain, barbell ones drop out.
        app.buttons["picker.equip.dumbbell"].tap()
        XCTAssertTrue(app.buttons["picker.row.Dumbbell Bench Press"].waitForExistence(timeout: 15),
                      "Dumbbell filter keeps Dumbbell Bench Press")
        XCTAssertFalse(app.buttons["picker.row.Bench Press"].waitForExistence(timeout: 3),
                       "Dumbbell filter must remove the barbell Bench Press")
    }

    /// Typing several characters must keep filtering responsively (no crash/hang)
    /// and narrow the results — a smoke test for the debounced, indexed search.
    func testIncrementalTypingNarrowsResults() {
        let app = openPicker()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "search field")
        field.tap()
        field.typeText("bench")

        XCTAssertTrue(app.buttons["picker.row.Bench Press"].waitForExistence(timeout: 10),
                      "‘bench’ should surface Bench Press")
        // A curl is not a bench movement — it must be filtered out.
        XCTAssertFalse(app.buttons["picker.row.Barbell Curl"].exists,
                       "unrelated exercises must be filtered out")
    }
}
