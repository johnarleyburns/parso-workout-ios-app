import XCTest

/// Post-save Home refresh (audio/coach routing plan §C): logging/completing a
/// workout must update Home's Coach surfaces immediately — without backgrounding
/// or re-entering the app. We assert via "Why this today" (reliably queryable),
/// per the plan's fallback of checking the Coach last-cardio fact rather than the
/// integer minute tile.
final class HomeRefreshUITests: CadenceUITestCase {

    /// Log a run, then — without relaunch — open "Why this today" and confirm the
    /// just-logged run is surfaced as the most recent cardio.
    func testLoggedCardioImmediatelyShowsAsLastCardio() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 10))

        // Log a run "now" via Log Workout.
        XCTAssertTrue(app.scrollToHittableAndTap("home.logWorkout"), "open Log Workout")
        XCTAssertTrue(app.buttons["logType.run"].waitTap(), "choose Run")
        XCTAssertTrue(app.buttons["log.save"].waitForExistence(timeout: 10), "log save button")
        app.buttons["log.save"].tap()

        // Back on Home without relaunch: the Coach surfaces must already reflect it.
        XCTAssertTrue(app.buttons["coach.card.whyToday"].waitForExistence(timeout: 10))
        app.buttons["coach.card.whyToday"].tap()
        _ = app.navigationBars["Why this today"].waitForExistence(timeout: 5)

        let lastCardio = app.descendants(matching: .any)["whyToday.fact.lastCardio"].firstMatch
        XCTAssertTrue(lastCardio.waitForExistence(timeout: 5),
                      "last cardio fact should exist immediately after logging")
        XCTAssertTrue(lastCardio.label.contains("Run"),
                      "the just-logged run should be the most recent cardio, got: \(lastCardio.label)")
    }
}
