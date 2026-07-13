import XCTest

/// Smoke: the core strength loop — start a workout, add an exercise, log a set.
/// The logging *logic* (rep ladders, prescriptions, last-weight, canonical kg) is
/// unit-tested in `SessionViewModelTests`; this proves the on-device flow.
/// Replaces FR1StrengthUITests / FR7LifecycleUITests / StrengthEditingUITests.
final class SmokeStrengthLoopTests: CadenceUITestCase {
    func testLogWorkoutEndToEnd() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.startEmptyStrengthWorkout(), "should land on the session screen")

        XCTAssertTrue(app.pickExercise("Bench Press"), "add Bench Press via the picker")
        app.recordKeypadSet("100")
        XCTAssertTrue(app.staticTexts["exerciseCard.Bench Press"].waitForExistence(timeout: 25),
                      "the exercise card should appear")
        app.dismissRestBar()
        XCTAssertTrue(app.buttons["set.row.Bench Press.0"].waitForExistence(timeout: 25),
                      "the logged set row should appear")
    }
}
