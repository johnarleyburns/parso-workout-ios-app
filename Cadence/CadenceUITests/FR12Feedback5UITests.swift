import XCTest

/// Feedback batch 5 (field-testing round 4B) — pre-workout HR connect screen,
/// live HR capture during intervals, and skip-phase. Updated for the Phase 1
/// HR gate redesign: the gate only appears when `useHRMonitoring` is ON.
final class FR12Feedback5UITests: CadenceUITestCase {

    // MARK: Helpers

    private func anyElement(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func startGibala(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["home.startWorkout"].waitTap(), "Start Workout")
        XCTAssertTrue(app.buttons["startType.hiit"].waitTap(), "HIIT type")
        XCTAssertTrue(app.buttons["interval.preset.gibala"].waitTap(), "Gibala preset")
        XCTAssertTrue(app.buttons["interval.start"].waitTap(), "START")
    }

    // MARK: HR gate OFF (default)

    func testNoHRGateWhenMonitoringOff() {
        let app = XCUIApplication.launched()
        startGibala(app)
        XCTAssertTrue(app.staticTexts["interval.countdown"].waitForExistence(timeout: 25),
                      "the interval runner should start directly (no HR gate)")
        XCTAssertFalse(anyElement(app, "interval.bpm").exists,
                       "no HR readout when monitoring is off")
    }

    // MARK: HR gate ON

    func testHRGateConnectStrapAndCapture() {
        let app = XCUIApplication.launched(extraArgs: ["-enableHRMonitoring"])
        startGibala(app)

        XCTAssertTrue(app.staticTexts["prehr.title"].waitForExistence(timeout: 25),
                      "the pre-workout HR screen should appear")
        XCTAssertTrue(app.buttons["prehr.connectStrap"].waitTap(), "Connect strap")
        XCTAssertTrue(anyElement(app, "prehr.strapBPM").waitForExistence(timeout: 10),
                      "the strap should show a live BPM after connecting")

        XCTAssertTrue(app.buttons["prehr.start"].waitTap(), "Start")
        XCTAssertTrue(anyElement(app, "interval.bpm").waitForExistence(timeout: 25),
                      "the interval screen should show a live HR readout")

        app.buttons["interval.end"].tap()
        XCTAssertTrue(app.buttons["workout.endConfirm"].waitTap(), "confirm End")
        XCTAssertTrue(app.otherElements["summary.hrChart"].waitForExistence(timeout: 25),
                      "the summary should show the captured HR chart")
        XCTAssertTrue(app.buttons["summary.done"].waitTap(), "Done")
    }

    // MARK: Skip any phase

    func testSkipAdvancesPhase() {
        let app = XCUIApplication.launched()
        startGibala(app)

        let phase = app.staticTexts["interval.phaseLabel"]
        XCTAssertTrue(phase.waitForExistence(timeout: 25), "phase label")
        XCTAssertTrue(phase.label.localizedCaseInsensitiveContains("WARM"),
                      "Gibala starts on a warm-up, was \(phase.label)")

        XCTAssertTrue(app.buttons["interval.skip"].waitTap(), "Skip the warm-up")
        let advanced = NSPredicate(format: "NOT (label CONTAINS[c] 'WARM')")
        expectation(for: advanced, evaluatedWith: phase)
        waitForExpectations(timeout: 10)
    }
}
