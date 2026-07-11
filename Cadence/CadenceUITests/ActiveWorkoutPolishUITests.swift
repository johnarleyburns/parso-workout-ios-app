import XCTest

/// P6 (issues 9 & 10) — active strength session improvements: wall clock, a Work/
/// Rest stopwatch, per-exercise info button, an "X" (not "Cancel") on the inline
/// editor, and a numeric RPE field.
final class ActiveWorkoutPolishUITests: CadenceUITestCase {

    func testStrengthSessionShowsWallClockAndWorkRestTimers() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.startEmptyStrengthWorkout(), "session screen")

        XCTAssertTrue(app.descendants(matching: .any)["workout.wallClock"].waitForExistence(timeout: 10),
                      "Strength session should show a wall clock (issue 10)")
        XCTAssertTrue(app.buttons["session.timer.work"].exists, "Work timer present (issue 9)")
        XCTAssertTrue(app.buttons["session.timer.rest"].exists, "Rest timer present (issue 9)")
    }

    func testExerciseHasInfoButtonOpeningDetail() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.startEmptyStrengthWorkout(), "session screen")
        app.buttons["session.addExercise"].tap()
        addBenchPress(app)

        let info = app.buttons["exercise.info.Bench Press"]
        XCTAssertTrue(info.waitForExistence(timeout: 10), "Each exercise should have an info button")
        // ExerciseDetailView shows the exercise name as its title (nav bar or heading).
        XCTAssertTrue(app.tapToReveal("exercise.info.Bench Press", "Bench Press"),
                      "Info opens the exercise definition page")
    }

    func testInlineEditorUsesXAndNumericRPE() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.startEmptyStrengthWorkout(), "session screen")
        app.buttons["session.addExercise"].tap()
        addBenchPress(app)

        // Adding a set opens the inline editor (or it may already be open).
        if app.buttons["set.add.Bench Press"].waitForExistence(timeout: 5) {
            app.buttons["set.add.Bench Press"].tap()
        }

        // The inline editor's dismiss control is an "X" (SF Symbol xmark) with the
        // a11y label "Cancel", not a text button labeled "Cancel".
        let cancel = app.buttons["inline.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "Inline editor has a close control")

        // RPE is a numeric field, not a +/- stepper.
        XCTAssertTrue(app.textFields["inline.rpeField"].waitForExistence(timeout: 5),
                      "RPE should be a numeric entry field")
    }

    /// Selects Bench Press in the picker, searching if the row isn't immediately
    /// shown, then confirms via the detail page's Add action.
    private func addBenchPress(_ app: XCUIApplication) {
        let row = app.buttons["picker.row.Bench Press"]
        if !row.waitForExistence(timeout: 5) {
            let search = app.searchFields.firstMatch
            if search.waitForExistence(timeout: 5) {
                search.tap()
                search.typeText("Bench Press")
            }
        }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Bench Press row")
        row.tap()
        // The row navigates to the exercise detail page; confirm with Add.
        let add = app.buttons["detail.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "detail Add action")
        add.tap()
    }
}
