import XCTest

/// The one normal iPhone XCUITest. It covers the minimum end-to-end surface that
/// needs a real simulator: launch, Home expansion, planning, Quick Start, ending,
/// and the post-workout summary. Everything else belongs in headless `swift test`.
final class SmokeLaunchTests: CadenceUITestCase {
    @MainActor
    func testIPhoneStrengthWorkoutPlansLogsAndCompletes() {
        let app = XCUIApplication.launched()

        XCTAssertEqual(app.state, .runningForeground,
                       "iPhone app terminated or failed to reach the foreground during cold launch")
        XCTAssertTrue(app.buttons["home.startWorkout"].waitForExistence(timeout: 25),
                      "Home did not load")
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10),
                      "Coach card did not render on Home")
        XCTAssertTrue(app.buttons["home.logWorkout"].waitForExistence(timeout: 5),
                      "Home did not show the previous-workout log action")

        XCTAssertTrue(app.scrollToHittableAndTap("home.week.showMore"),
                      "This Week did not offer Show more")
        XCTAssertTrue(app.descendants(matching: .any)["home.thisWeek.expanded"].waitForExistence(timeout: 5),
                      "This Week did not expand in place")
        XCTAssertTrue(app.scrollToHittableAndTap("home.week.showLess"),
                      "Expanded This Week did not show Show less")

        XCTAssertTrue(app.scrollToHittableAndTap("tab.plan"), "Plan tab did not open")
        XCTAssertTrue(app.descendants(matching: .any)["planning"].waitForExistence(timeout: 10),
                      "Programs screen did not render")
        app.popToHome()

        XCTAssertTrue(app.startEmptyStrengthWorkout(), "Quick Start did not enter the workout")
        XCTAssertFalse(app.buttons["editor.showSettings"].exists,
                       "Quick Start unexpectedly opened workout settings")

        XCTAssertTrue(app.scrollToHittableAndTap("workout.end"), "End workout button did not tap")
        let end = app.dialogButton("workout.endConfirm")
        XCTAssertTrue(end.waitForExistence(timeout: 5), "End confirmation did not appear")
        end.tap()

        XCTAssertTrue(app.descendants(matching: .any)["summary.title"].waitForExistence(timeout: 15),
                      "post-workout summary did not render")
        XCTAssertTrue(app.buttons["summary.done"].waitTap(timeout: 10), "summary Done did not tap")
        XCTAssertTrue(app.buttons["home.startWorkout"].waitForExistence(timeout: 10),
                      "Home did not return after summary")
    }
}
