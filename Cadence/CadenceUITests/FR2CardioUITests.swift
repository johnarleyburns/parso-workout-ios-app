import XCTest

/// UI tests for FR-2 cardio. Run on iPhone and iPad.
final class FR2CardioUITests: CadenceUITestCase {

    // FR-2.1 — sync ingests a Watch workout and de-duplicates on re-sync.
    func testSyncIngestsAndDeduplicates() {
        let app = XCUIApplication.launched()
        app.goToTab("Cardio")
        // Auto-sync on first appear should surface the fake Watch run.
        XCTAssertTrue(app.buttons["cardioRow.run"].waitForExistence(timeout: 10),
                      "a synced run should appear")
        let countAfterFirst = app.buttons.matching(identifier: "cardioRow.run").count

        // Manual re-sync must not duplicate (dedup by HealthKit UUID).
        app.buttons["cardio.sync"].tap()
        XCTAssertTrue(app.staticTexts["cardio.syncMessage"].waitForExistence(timeout: 10))
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
        XCTAssertTrue(elapsed.waitForExistence(timeout: 10))
        // Elapsed should advance past 0:00 (the 1s timer is running).
        expectation(for: NSPredicate(format: "label != %@", "0:00"), evaluatedWith: elapsed)
        waitForExpectations(timeout: 8)
        // GPS distance tile should be present for an outdoor run.
        XCTAssertTrue(app.staticTexts["record.distance"].exists, "distance metric for GPS run")

        app.buttons["record.end"].tap()
        // Back on the Cardio list, a run should be in history.
        XCTAssertTrue(app.buttons["cardioRow.run"].waitForExistence(timeout: 10),
                      "recorded run should appear in history")
    }

    // FR-2.3 — connect a chest strap during recording and read live HR.
    func testConnectStrapLiveHR() {
        let app = XCUIApplication.launched()
        app.goToTab("Cardio")
        app.buttons["cardio.record"].waitTap()
        app.buttons["record.start.boxing"].waitTap()

        let connect = app.buttons["record.connectStrap"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        connect.tap()
        XCTAssertTrue(app.staticTexts["record.strapConnected"].waitForExistence(timeout: 10)
                      || app.images["record.strapConnected"].waitForExistence(timeout: 2),
                      "strap should report connected")
        // Live HR should become a number, not the placeholder.
        let hr = app.staticTexts["record.hr"]
        expectation(for: NSPredicate(format: "label != %@", "—"), evaluatedWith: hr)
        waitForExpectations(timeout: 8)
    }
}
