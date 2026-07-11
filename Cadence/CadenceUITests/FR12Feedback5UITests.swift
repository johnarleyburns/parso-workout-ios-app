import XCTest

/// Feedback batch 5 (field-testing round 4B) — the pre-workout HR connect screen
/// for HIIT/boxing, live HR capture during intervals, and the ability to skip any
/// interval phase (warm-up/work/rest/cool-down).
final class FR12Feedback5UITests: CadenceUITestCase {

    // MARK: Helpers

    /// Match an accessibility id regardless of element type — combined HR readouts
    /// can surface as `.staticText` or `.other`.
    private func anyElement(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Start a Gibala HIIT interval up to the pre-workout HR gate.
    private func startGibalaToHRGate(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["home.startCardio"].waitTap(), "Start Cardio")
        XCTAssertTrue(app.buttons["startType.hiit"].waitTap(), "HIIT type")
        XCTAssertTrue(app.buttons["interval.preset.gibala"].waitTap(), "Gibala preset")
        XCTAssertTrue(app.buttons["interval.start"].waitTap(), "START")
        XCTAssertTrue(app.staticTexts["prehr.title"].waitForExistence(timeout: 25),
                      "the pre-workout HR screen should appear")
    }

    // MARK: HR gate

    // The HR gate appears before the runner; "Continue without HR" starts the
    // workout with no HR readout.
    func testHRGateContinueWithout() {
        let app = XCUIApplication.launched()
        startGibalaToHRGate(app)
        XCTAssertTrue(app.buttons["prehr.skip"].waitTap(), "Continue without HR")
        XCTAssertTrue(app.staticTexts["interval.countdown"].waitForExistence(timeout: 25),
                      "the interval runner should start")
        XCTAssertFalse(anyElement(app, "interval.bpm").exists,
                       "no HR readout when continuing without HR")
    }

    // Connecting the strap shows a live BPM, and "Use this HR" carries it into the
    // workout (a live readout) and the saved summary (an HR chart).
    func testHRGateConnectStrapAndCapture() {
        let app = XCUIApplication.launched()
        startGibalaToHRGate(app)

        XCTAssertTrue(app.buttons["prehr.connectStrap"].waitTap(), "Connect strap")
        XCTAssertTrue(anyElement(app, "prehr.strapBPM").waitForExistence(timeout: 10),
                      "the strap should show a live BPM after connecting")

        XCTAssertTrue(app.buttons["prehr.useHR"].waitTap(), "Use this HR")
        XCTAssertTrue(anyElement(app, "interval.bpm").waitForExistence(timeout: 25),
                      "the interval screen should show a live HR readout")

        app.buttons["interval.end"].tap()
        XCTAssertTrue(app.dialogButton("workout.endConfirm").waitTap(), "confirm End")
        XCTAssertTrue(app.otherElements["summary.hrChart"].waitForExistence(timeout: 25),
                      "the summary should show the captured HR chart")
        XCTAssertTrue(app.buttons["summary.done"].waitTap(), "Done")
    }

    // MARK: Skip any phase

    // Gibala opens on a warm-up phase; Skip advances to the first work round.
    func testSkipAdvancesPhase() {
        let app = XCUIApplication.launched()
        startGibalaToHRGate(app)
        XCTAssertTrue(app.buttons["prehr.skip"].waitTap(), "Continue without HR")

        let phase = app.staticTexts["interval.phaseLabel"]
        XCTAssertTrue(phase.waitForExistence(timeout: 25), "phase label")
        XCTAssertTrue(phase.label.localizedCaseInsensitiveContains("WARM"),
                      "Gibala starts on a warm-up, was \(phase.label)")

        XCTAssertTrue(app.buttons["interval.skip"].waitTap(), "Skip the warm-up")
        // The label should advance off the warm-up (to a work round).
        let advanced = NSPredicate(format: "NOT (label CONTAINS[c] 'WARM')")
        expectation(for: advanced, evaluatedWith: phase)
        waitForExpectations(timeout: 10)
    }
}
