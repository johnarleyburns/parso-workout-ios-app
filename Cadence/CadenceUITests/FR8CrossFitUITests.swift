import XCTest

/// Field-testing Round 4 Part B-1 (FR-8 CrossFit) — the benchmark entry point.
/// Start → CrossFit lists "The Girls"; a benchmark previews its Rx prescription;
/// Start launches a planned session with the scheme banner + per-movement Rx, and
/// the movements log through the normal strength flow (set editor → summary).
final class FR8CrossFitUITests: CadenceUITestCase {

    // Helper: Home → Start Workout → CrossFit type (no countdown).
    private func openCrossFitPicker() -> XCUIApplication {
        let app = XCUIApplication.launched(extraArgs: ["-preCountdown", "0"])
        XCTAssertTrue(app.buttons["home.startWorkout"].waitTap(), "Start Workout")
        XCTAssertTrue(app.buttons["startType.crossfit"].waitTap(), "CrossFit type")
        return app
    }

    // B-1 — the CrossFit picker lists the benchmark "Girls" (e.g. Fran), and a row
    // opens a preview showing the scheme summary + Rx prescription.
    func testCrossFitPickerListsBenchmarksAndPreviewsRx() {
        let app = openCrossFitPicker()

        let fran = app.buttons["crossfit.row.fran"]
        XCTAssertTrue(fran.waitForExistence(timeout: 25), "Fran should be listed")
        fran.tap()

        let scheme = app.staticTexts["crossfit.preview.scheme"]
        XCTAssertTrue(scheme.waitForExistence(timeout: 10), "preview should show the scheme")
        XCTAssertTrue(scheme.label.contains("21-15-9"), "Fran is a 21-15-9 ladder")
        XCTAssertTrue(app.buttons["crossfit.preview.start"].exists, "preview offers Start")
    }

    // B-1 — starting a benchmark opens a planned session: the scheme banner shows
    // the ladder, and each prescribed movement appears as a planned card with Rx.
    func testStartingFranOpensPlannedSession() {
        let app = openCrossFitPicker()
        XCTAssertTrue(app.buttons["crossfit.row.fran"].waitTap(), "Fran row")
        XCTAssertTrue(app.buttons["crossfit.preview.start"].waitTap(), "Start Fran")

        let banner = app.staticTexts["session.planBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 25), "the session shows a scheme banner")
        XCTAssertTrue(banner.label.contains("21-15-9"), "banner reflects Fran's ladder")

        XCTAssertTrue(app.staticTexts["exerciseCard.Thruster"].waitForExistence(timeout: 10),
                      "Fran's Thruster should be pre-loaded as a planned card")
        XCTAssertTrue(app.staticTexts["session.rx.Thruster"].exists,
                      "the Thruster card shows its prescription")
        XCTAssertTrue(app.staticTexts["exerciseCard.Pull-Up"].exists,
                      "Fran's Pull-Up should be pre-loaded too")
    }

    // B-1 — a prescribed movement logs through the normal strength flow, and End
    // produces the always-on summary listing that movement.
    func testLoggingAndEndingABenchmark() {
        let app = openCrossFitPicker()
        XCTAssertTrue(app.buttons["crossfit.row.fran"].waitTap(), "Fran row")
        XCTAssertTrue(app.buttons["crossfit.preview.start"].waitTap(), "Start Fran")
        XCTAssertTrue(app.staticTexts["session.planBanner"].waitForExistence(timeout: 25), "session")

        // Log one Thruster set from its planned card.
        XCTAssertTrue(app.buttons["set.add.Thruster"].waitTap(), "Add Set on Thruster")
        let weight = app.textFields["set.weight"]
        XCTAssertTrue(weight.waitForExistence(timeout: 25), "set editor")
        weight.tap()
        weight.typeText("95")
        app.buttons["set.save"].tap()
        if app.buttons["rest.skip"].waitForExistence(timeout: 3) { app.buttons["rest.skip"].tap() }

        // End → confirm → summary lists the logged movement.
        XCTAssertTrue(app.buttons["workout.end"].waitTap(), "End")
        XCTAssertTrue(app.buttons["workout.endConfirm"].waitTap(), "confirm End")
        XCTAssertTrue(app.staticTexts["summary.exercise.Thruster"].waitForExistence(timeout: 25),
                      "the summary should list the logged Thruster")
        XCTAssertTrue(app.buttons["summary.done"].waitTap(), "Done")
        XCTAssertTrue(app.buttons["home.startWorkout"].waitForExistence(timeout: 25),
                      "Done leaves the session and returns Home")
    }
}
