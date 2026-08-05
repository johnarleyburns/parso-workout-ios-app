import XCTest

/// The one normal iPhone XCUITest. It covers the minimum end-to-end surface that
/// needs a real simulator: launch, planning, starting, logging, ending, and the
/// post-workout summary. Everything else belongs in headless `swift test`.
final class SmokeLaunchTests: CadenceUITestCase {
    func testIPhoneStrengthWorkoutPlansLogsAndCompletes() {
        let app = XCUIApplication.launched()

        XCTAssertTrue(app.buttons["home.startWorkout"].waitForExistence(timeout: 25),
                      "Home did not load")
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10),
                      "Coach card did not render on Home")

        XCTAssertTrue(app.scrollToHittableAndTap("home.planning"), "Programs shortcut did not open")
        XCTAssertTrue(app.descendants(matching: .any)["planning"].waitForExistence(timeout: 10),
                      "Programs screen did not render")
        app.popToHome()

        XCTAssertTrue(app.openQuickStartStrengthEditor(), "Quick Start editor did not open")
        XCTAssertTrue(app.addExerciseToOpenWorkoutPlan("Bench Press"),
                      "could not add Bench Press to the workout plan")

        XCTAssertTrue(app.buttons["editor.start"].waitTap(timeout: 10), "planned workout did not start")
        XCTAssertTrue(app.buttons["set.add.Bench Press"].waitTap(timeout: 25),
                      "planned Bench Press card did not render")

        let weightField = app.textFields["set.weightField"]
        XCTAssertTrue(weightField.waitForExistence(timeout: 10),
                      "inline set editor did not open for planned exercise (add-set regression)")
        weightField.tap()
        weightField.typeText("40")

        app.buttons["set.save"].tap()

        // The set must land as a completed row on the card.
        XCTAssertTrue(app.buttons["set.editWeight.Bench Press.1"].waitForExistence(timeout: 10),
                      "logged set row did not appear")
        app.dismissRestBar()

        XCTAssertTrue(app.scrollToHittableAndTap("workout.end"), "End workout button did not tap")
        let end = app.dialogButton("workout.endConfirm")
        XCTAssertTrue(end.waitForExistence(timeout: 5), "End confirmation did not appear")
        end.tap()

        XCTAssertTrue(app.descendants(matching: .any)["summary.title"].waitForExistence(timeout: 15),
                      "post-workout summary did not render")
        XCTAssertTrue(app.descendants(matching: .any)["summary.metric.sets"].waitForExistence(timeout: 5),
                      "summary did not show set count")
        XCTAssertTrue(app.buttons["summary.done"].waitTap(timeout: 10), "summary Done did not tap")
        XCTAssertTrue(app.buttons["home.startWorkout"].waitForExistence(timeout: 10),
                      "Home did not return after summary")
    }
}
