import XCTest

/// Smoke: a real interval workout runs against the wall clock and summarizes.
/// The interval engine + cue-timing are unit-tested (`IntervalRunnerTests`,
/// `IntervalCueDeciderTests`); this proves the runner UI + audio path on-device.
/// Replaces FR2IntervalsUITests / FR2CardioUITests / FR12Feedback5UITests.
final class SmokeIntervalTests: CadenceUITestCase {
    func testIntervalRunsAndSummarizes() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.startCardio"].waitTap(), "Start Cardio")
        XCTAssertTrue(app.buttons["startType.boxing"].waitTap(), "Boxing type")
        XCTAssertTrue(app.buttons["interval.start"].waitTap(), "START")

        XCTAssertTrue(app.staticTexts["interval.countdown"].waitForExistence(timeout: 25),
                      "interval countdown should render")
        app.buttons["interval.pause"].tap()
        app.buttons["interval.end"].tap()
        XCTAssertTrue(app.dialogButton("workout.endConfirm").waitTap(), "confirm End")
        XCTAssertTrue(app.buttons["summary.done"].waitTap(), "the interval summary should appear")
    }
}
