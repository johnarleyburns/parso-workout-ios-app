import XCTest

/// Post-save Home refresh (audio/coach routing plan §C): logging/completing a
/// workout must update Home's Coach-derived surfaces immediately — without
/// backgrounding or re-entering the app.
final class HomeRefreshUITests: CadenceUITestCase {

    /// Log a run, then — without relaunch — confirm the just-logged run is
    /// surfaced as the most recent cardio in Home's "What you did" summary.
    func testLoggedCardioImmediatelyShowsAsLastCardio() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10))

        // Log a run "now" via Log Workout.
        XCTAssertTrue(app.scrollToHittableAndTap("home.logWorkout"), "open Log Workout")
        XCTAssertTrue(app.buttons["logType.run"].waitTap(), "choose Run")
        XCTAssertTrue(app.buttons["log.save"].waitForExistence(timeout: 10), "log save button")
        app.buttons["log.save"].tap()

        // Back on Home without relaunch: the Coach-derived facts must already reflect it.
        let lastCardio = app.descendants(matching: .any)["home.fact.lastCardio"].firstMatch
        for _ in 0..<8 where !lastCardio.exists {
            app.swipeUp()
        }
        XCTAssertTrue(lastCardio.exists,
                      "last cardio fact should exist immediately after logging")
        XCTAssertTrue(lastCardio.label.contains("Run"),
                      "the just-logged run should be the most recent cardio, got: \(lastCardio.label)")
    }
}
