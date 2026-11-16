import XCTest

/// One real-device smoke flow for the compact launcher and manual logging.
/// Never execute this suite in CI or a simulator.
final class SmokeLaunchTests: CadenceUITestCase {
    @MainActor
    func testIPhoneStrengthWorkoutPlansLogsAndCompletes() {
        let app = XCUIApplication.launched(seeds: ["person.Sam"])
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.buttons["home.start.workout"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.buttons["home.start.workoutSource"].exists)
        XCTAssertFalse(app.buttons["home.start.cardio"].exists)
        XCTAssertFalse(app.buttons["selectWorkout.startWorkout"].exists)
        XCTAssertFalse(app.buttons["editor.schedule"].exists)
        XCTAssertTrue(app.startEmptyStrengthWorkout())
        XCTAssertTrue(app.pickExercise("Bench Press"))
        XCTAssertTrue(app.scrollToHittableAndTap("set.add.Bench Press"))
        XCTAssertTrue(app.saveSetInEditor())
        app.dismissRestBar()
        XCTAssertTrue(app.buttons["workout.end"].waitTap(timeout: 10))
        XCTAssertTrue(app.dialogButton("workout.endConfirm").waitTap(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["summary.title"].waitForExistence(timeout: 15))

        // Repeat-last-workout (#741): back on Today, the just-completed session
        // is now history, so the quick-repeat row opens a pre-filled editor and
        // starting it begins a new session the same way Quick Start does.
        XCTAssertTrue(app.buttons["summary.done"].waitTap(timeout: 10))
        XCTAssertTrue(app.scrollToHittableAndTap("home.repeatLastWorkout"))
        XCTAssertTrue(app.descendants(matching: .any)["workoutEditor.plan"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["editor.start"].waitTap(timeout: 10))
        if app.buttons["prehr.start"].waitForExistence(timeout: 3) { app.buttons["prehr.start"].tap() }
        XCTAssertTrue(app.buttons["session.addExercise"].waitForExistence(timeout: 25))
    }
}
