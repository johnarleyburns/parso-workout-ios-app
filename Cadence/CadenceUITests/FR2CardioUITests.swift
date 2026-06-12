import XCTest

/// UI tests for FR-2 cardio. Run on iPhone and iPad.
final class FR2CardioUITests: CadenceUITestCase {

    // FR-2.1 — sync ingests a Watch workout and de-duplicates on re-sync.
    func testSyncIngestsAndDeduplicates() {
        let app = XCUIApplication.launched()
        app.goToTab("Cardio")
        // Auto-sync on first appear should surface the fake Watch run.
        XCTAssertTrue(app.buttons["cardioRow.run"].waitForExistence(timeout: 25),
                      "a synced run should appear")
        let countAfterFirst = app.buttons.matching(identifier: "cardioRow.run").count

        // Manual re-sync must not duplicate (dedup by HealthKit UUID).
        app.buttons["cardio.sync"].tap()
        XCTAssertTrue(app.staticTexts["cardio.syncMessage"].waitForExistence(timeout: 25))
        let countAfterSecond = app.buttons.matching(identifier: "cardioRow.run").count
        XCTAssertEqual(countAfterFirst, countAfterSecond, "re-sync should not duplicate")
    }

    // FR-2.2 / 2.4 / 2.5 — record an outdoor run with live metrics, save to history.
    func testRecordOutdoorRun() {
        let app = XCUIApplication.launched()
        app.goToTab("Cardio")
        app.buttons["cardio.record"].waitTap()
        app.buttons["record.start.run"].waitTap()

        let elapsed = app.staticTexts["record.elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 25))
        // Elapsed should advance past 0:00 (the 1s timer is running).
        expectation(for: NSPredicate(format: "label != %@", "0:00"), evaluatedWith: elapsed)
        waitForExpectations(timeout: 20)
        // GPS distance tile should be present for an outdoor run.
        XCTAssertTrue(app.staticTexts["record.distance"].exists, "distance metric for GPS run")

        app.buttons["record.end"].tap()
        XCTAssertTrue(app.buttons["workout.endConfirm"].waitTap(), "confirm End")
        // Back on the Cardio list, a run should be in history.
        XCTAssertTrue(app.buttons["cardioRow.run"].waitForExistence(timeout: 25),
                      "recorded run should appear in history")
    }

    // Field-testing §05 — Start Workout → Run opens the purpose-built outdoor
    // GPS screen with a live map and advancing metrics, saved to history.
    func testOutdoorRunViaHome() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.startWorkout"].waitTap(), "Start Workout")
        XCTAssertTrue(app.buttons["startType.run"].waitTap(), "Run type")

        let elapsed = app.staticTexts["outdoor.elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 25), "outdoor GPS screen")
        XCTAssertTrue(app.staticTexts["outdoor.distance"].exists, "distance metric")
        XCTAssertTrue(app.otherElements["outdoor.map"].waitForExistence(timeout: 10)
                      || app.maps.firstMatch.waitForExistence(timeout: 5), "live route map")
        // Elapsed should advance past 0:00.
        expectation(for: NSPredicate(format: "label != %@", "0:00"), evaluatedWith: elapsed)
        waitForExpectations(timeout: 20)

        app.buttons["outdoor.end"].tap()
        XCTAssertTrue(app.buttons["workout.endConfirm"].waitTap(), "confirm End")
        // Back on Home; the run is now in history.
        XCTAssertTrue(app.buttons["home.startWorkout"].waitForExistence(timeout: 25))
        app.goToTab("Cardio")
        XCTAssertTrue(app.buttons["cardioRow.run"].waitForExistence(timeout: 25),
                      "recorded outdoor run should appear in history")
    }

    // FR-2.3 — connect a chest strap during recording and read live HR.
    func testConnectStrapLiveHR() {
        let app = XCUIApplication.launched()
        app.goToTab("Cardio")
        app.buttons["cardio.record"].waitTap()
        app.buttons["record.start.boxing"].waitTap()

        let connect = app.buttons["record.connectStrap"]
        XCTAssertTrue(connect.waitForExistence(timeout: 25))
        connect.tap()
        XCTAssertTrue(app.staticTexts["record.strapConnected"].waitForExistence(timeout: 25)
                      || app.images["record.strapConnected"].waitForExistence(timeout: 2),
                      "strap should report connected")
        // Live HR should become a number, not the placeholder.
        let hr = app.staticTexts["record.hr"]
        expectation(for: NSPredicate(format: "label != %@", "—"), evaluatedWith: hr)
        waitForExpectations(timeout: 20)
    }
}
