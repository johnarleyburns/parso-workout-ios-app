import XCTest

/// One real-device smoke flow for the compact launcher and manual logging.
/// Never execute this suite in CI or a simulator.
final class SmokeLaunchTests: CadenceUITestCase {
    @MainActor
    func testIPhoneStrengthWorkoutPlansLogsAndCompletes() {
        let app = XCUIApplication.launched(seeds: ["person.Sam"])
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.buttons["home.start.strength"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.buttons["home.start.cardio"].exists)
        XCTAssertFalse(app.buttons["selectWorkout.startWorkout"].exists)
        XCTAssertFalse(app.buttons["editor.schedule"].exists)
        XCTAssertTrue(app.startEmptyStrengthWorkout())
        XCTAssertTrue(app.pickExercise("Bench Press"))
        XCTAssertTrue(app.saveSetInEditor())
        app.dismissRestBar()
        XCTAssertTrue(app.buttons["workout.end"].waitTap(timeout: 10))
        XCTAssertTrue(app.dialogButton("workout.endConfirm").waitTap(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["summary.title"].waitForExistence(timeout: 15))
    }
}
