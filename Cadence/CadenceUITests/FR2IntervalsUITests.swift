import XCTest

/// Field-testing §06 / round 3 — HIIT & boxing interval engine. Selecting a
/// preset no longer auto-starts; a prominent START launches it.
final class FR2IntervalsUITests: CadenceUITestCase {

    func testBoxingIntervalViaHome() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.startCardio"].waitTap(), "Start Cardio")
        XCTAssertTrue(app.buttons["startType.boxing"].waitTap(), "Boxing type")

        // Boxing no longer has presets; the Details steppers appear with defaults
        // (Warm-up 5 min, Rounds 8, Fighting 3:00, Rest 60 s, Cool-down 5 min).
        // Just tap START.
        XCTAssertTrue(app.buttons["interval.start"].waitTap(), "START")

        // Full-screen runner shows the protocol name + countdown.
        XCTAssertTrue(app.staticTexts["interval.countdown"].waitForExistence(timeout: 25),
                      "interval countdown should render")
        XCTAssertTrue(app.staticTexts["interval.planName"].exists, "protocol name persists")
        app.buttons["interval.pause"].tap()
        app.buttons["interval.end"].tap()
        XCTAssertTrue(app.buttons["workout.endConfirm"].waitTap(), "confirm End")
        // A3 — the interval summary appears; Done returns Home.
        XCTAssertTrue(app.buttons["summary.done"].waitTap(), "summary Done")

        XCTAssertTrue(app.buttons["home.startWorkout"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.scrollToHittableAndTap("home.train"), "open History")
        XCTAssertTrue(app.buttons["history.cardioRow.boxing"].waitForExistence(timeout: 25),
                      "boxing session should be saved to history")
    }

    func testHIITPresetsAndStart() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.startCardio"].waitTap(), "Start Cardio")
        XCTAssertTrue(app.buttons["startType.hiit"].waitTap(), "HIIT type")
        // All six science-backed presets are offered.
        for id in ["tabata", "norwegian", "gibala", "sit", "ten", "rehit"] {
            XCTAssertTrue(app.buttons["interval.preset.\(id)"].waitForExistence(timeout: 15),
                          "\(id) preset should be listed")
        }
        // Select Gibala, then START → runner shows its name.
        app.buttons["interval.preset.gibala"].tap()
        XCTAssertTrue(app.buttons["interval.start"].waitTap(), "START")
        XCTAssertTrue(app.staticTexts["interval.countdown"].waitForExistence(timeout: 25),
                      "runner should start")
        app.buttons["interval.end"].tap()
        XCTAssertTrue(app.buttons["workout.endConfirm"].waitTap(), "confirm End")
        // A3 — the summary appears after End.
        XCTAssertTrue(app.buttons["summary.done"].waitTap(), "summary Done")
    }
}
