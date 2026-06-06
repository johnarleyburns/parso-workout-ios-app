import XCTest

/// UI tests for FR-4 data, HealthKit & sensors. Run on iPhone and iPad.
final class FR4DataSensorsUITests: CadenceUITestCase {

    // FR-4.1 — in-context priming then authorization.
    func testHealthPriming() {
        let app = XCUIApplication.launched()
        app.goToTab("Settings")
        app.buttons["settings.health.connect"].waitTap()
        XCTAssertTrue(app.staticTexts["Connect Apple Health"].waitForExistence(timeout: 25),
                      "priming sheet should appear before the system prompt")
        XCTAssertTrue(app.buttons["health.priming.continue"].waitTap(), "continue button")
        let status = app.staticTexts["settings.health.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 25))
        expectation(for: NSPredicate(format: "label == %@", "Connected"), evaluatedWith: status)
        waitForExpectations(timeout: 20)
    }

    // FR-4.4 — discover and connect a chest strap, see live HR + battery.
    func testHRMPairing() {
        let app = XCUIApplication.launched()
        app.goToTab("Settings")
        app.buttons["settings.hrm"].waitTap()
        // Scanning starts on appear; connect the first discovered device.
        let connect = app.buttons["hrm.connect.Garmin HRM-Pro"]
        XCTAssertTrue(connect.waitForExistence(timeout: 25), "discovered device should appear")
        connect.tap()
        // A live BPM readout in the "My Device" section proves it connected.
        let bpm = app.staticTexts["hrm.bpm"]
        XCTAssertTrue(bpm.waitForExistence(timeout: 25), "live BPM should appear after connect")
        XCTAssertTrue(app.staticTexts["hrm.battery"].exists, "battery should be shown")
    }

    // FR-4.5 — iCloud sync toggle persists.
    func testCloudSyncToggle() {
        let app = XCUIApplication.launched()
        app.goToTab("Settings")
        let toggle = app.switches["settings.cloudSync"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 25))
        let before = (toggle.value as? String) ?? "0"
        // The row-level switch element's center is the label; tap the control edge.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let after = (toggle.value as? String) ?? "0"
        XCTAssertNotEqual(before, after, "iCloud sync toggle should flip")
    }

    // FR-4.3 — save a summary strength workout to Apple Health.
    func testSaveStrengthToHealth() {
        let app = XCUIApplication.launched()
        app.goToTab("Train")
        app.buttons["train.newWorkout"].waitTap()
        app.buttons["session.addExercise"].waitTap()
        app.buttons["picker.row.Bench Press"].waitTap()
        let weight = app.textFields["set.weight"]
        XCTAssertTrue(weight.waitForExistence(timeout: 25))
        weight.tap(); weight.typeText("100")
        app.buttons["set.save"].tap()

        app.buttons["session.saveHealth"].waitTap()
        XCTAssertTrue(app.staticTexts["session.healthSaved"].waitForExistence(timeout: 25),
                      "a saved-to-Health confirmation should appear")
    }
}
