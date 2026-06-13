import XCTest

/// UI tests for FR-2 cardio. The dedicated Cardio screen was removed in feedback
/// batch 3: cardio is recorded from Start Workout and reviewed in Home's recent
/// list / unified history. Sync now runs automatically on Home's appear.
final class FR2CardioUITests: CadenceUITestCase {

    // FR-2.1 — auto-sync on Home surfaces a Watch-recorded run. (Dedup by
    // HealthKit UUID is covered by CadenceCore's repository tests.)
    func testSyncSurfacesWatchRunOnHome() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.cardioRow.run"].waitForExistence(timeout: 25),
                      "a synced Watch run should appear in Home's recent workouts")
    }

    // Field-testing §05 — Start Workout → Run opens the purpose-built outdoor GPS
    // screen with a live map and advancing metrics, saved to history.
    func testOutdoorRunViaHome() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.startWorkout"].waitTap(), "Start Workout")
        XCTAssertTrue(app.buttons["startType.run"].waitTap(), "Run type")

        let elapsed = app.staticTexts["outdoor.elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 25), "outdoor GPS screen")
        XCTAssertTrue(app.staticTexts["outdoor.distance"].exists, "distance metric")
        XCTAssertTrue(app.otherElements["outdoor.map"].waitForExistence(timeout: 10)
                      || app.maps.firstMatch.waitForExistence(timeout: 5), "live route map")
        expectation(for: NSPredicate(format: "label != %@", "0:00"), evaluatedWith: elapsed)
        waitForExpectations(timeout: 20)

        app.buttons["outdoor.end"].tap()
        XCTAssertTrue(app.buttons["workout.endConfirm"].waitTap(), "confirm End")
        // A3 — the run summary appears (with distance/route); Done returns Home.
        XCTAssertTrue(app.staticTexts["summary.metric.distance"].waitForExistence(timeout: 25),
                      "outdoor run summary should show distance")
        XCTAssertTrue(app.buttons["summary.done"].waitTap(), "summary Done")
        // Back on Home; the recorded run is now in the recent list.
        XCTAssertTrue(app.buttons["home.cardioRow.run"].waitForExistence(timeout: 25),
                      "recorded outdoor run should appear in Home history")
    }

    // FR-2.3 — connect a chest strap during an indoor recording and read live HR.
    // Start Workout → Other opens the indoor recorder (RecordCardioView).
    func testConnectStrapLiveHR() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.startWorkout"].waitTap(), "Start Workout")
        XCTAssertTrue(app.buttons["startType.other"].waitTap(), "Other type")

        XCTAssertTrue(app.staticTexts["record.elapsed"].waitForExistence(timeout: 25), "recording")
        let connect = app.buttons["record.connectStrap"]
        XCTAssertTrue(connect.waitForExistence(timeout: 25))
        connect.tap()
        XCTAssertTrue(app.staticTexts["record.strapConnected"].waitForExistence(timeout: 25)
                      || app.images["record.strapConnected"].waitForExistence(timeout: 2),
                      "strap should report connected")
        let hr = app.staticTexts["record.hr"]
        expectation(for: NSPredicate(format: "label != %@", "—"), evaluatedWith: hr)
        waitForExpectations(timeout: 20)
    }

    // FR-2.3 / 5.3 — a synced cardio workout's summary shows its HR chart.
    func testCardioSummaryShowsHR() {
        let app = XCUIApplication.launched()
        let row = app.buttons["home.cardioRow.run"]
        XCTAssertTrue(row.waitForExistence(timeout: 25), "synced run row")
        row.tap()
        XCTAssertTrue(app.otherElements["summary.hrChart"].waitForExistence(timeout: 25)
                      || app.staticTexts["Heart Rate"].waitForExistence(timeout: 15),
                      "HR chart should render in the cardio summary")
    }
}
