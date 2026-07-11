import XCTest

/// UI tests for FR-2 cardio. The dedicated Cardio screen was removed in feedback
/// batch 3: cardio is recorded from Start Workout and reviewed in Home's summary
/// / unified history. Sync now runs automatically on Home's appear.
final class FR2CardioUITests: CadenceUITestCase {

    // FR-2.1 — auto-sync on Home surfaces a Watch-recorded run. (Dedup by
    // HealthKit UUID is covered by CadenceCore's repository tests.)
    func testSyncSurfacesWatchRunOnHome() {
        let app = XCUIApplication.launched()
        let lastCardio = app.descendants(matching: .any)["home.fact.lastCardio"].firstMatch
        for _ in 0..<8 where !lastCardio.exists { app.swipeUp() }
        XCTAssertTrue(lastCardio.exists,
                      "a synced Watch run should appear in Home's latest cardio fact")
        XCTAssertTrue(lastCardio.label.contains("Run"))
    }

    // Field-testing §05 — Start Workout → Run opens the purpose-built outdoor GPS
    // screen with a live map and advancing metrics, saved to history.
    func testOutdoorRunViaHome() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.startCardio"].waitTap(), "Start Cardio")
        XCTAssertTrue(app.buttons["startType.run"].waitTap(), "Run type")
        // Run/Walk/Cycle now offer an optional distance goal first (batch 8); skip it.
        XCTAssertTrue(app.buttons["goal.none"].waitTap(), "skip distance goal")

        let elapsed = app.staticTexts["outdoor.elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 25), "outdoor GPS screen")
        XCTAssertTrue(app.staticTexts["outdoor.distance"].exists, "distance metric")
        XCTAssertTrue(app.otherElements["outdoor.map"].waitForExistence(timeout: 10)
                      || app.maps.firstMatch.waitForExistence(timeout: 5), "live route map")
        expectation(for: NSPredicate(format: "label != %@", "0:00"), evaluatedWith: elapsed)
        waitForExpectations(timeout: 20)

        app.buttons["outdoor.end"].tap()
        XCTAssertTrue(app.dialogButton("workout.endConfirm").waitTap(), "confirm End")
        // A3 — the run summary appears (with distance/route); Done returns Home.
        XCTAssertTrue(app.staticTexts["summary.metric.distance"].waitForExistence(timeout: 25),
                      "outdoor run summary should show distance")
        XCTAssertTrue(app.buttons["summary.done"].waitTap(), "summary Done")
        // Back on Home; the recorded run is now reflected in the latest cardio fact.
        let lastCardio = app.descendants(matching: .any)["home.fact.lastCardio"].firstMatch
        for _ in 0..<8 where !lastCardio.exists { app.swipeUp() }
        XCTAssertTrue(lastCardio.exists,
                      "recorded outdoor run should appear in Home's latest cardio fact")
    }

    // FR-2.3 — live HR shown during an indoor recording when strap is connected
    // pre-workout. Start Workout → Other opens the indoor recorder.
    func testIndoorRecordingShowsMetrics() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["home.startCardio"].waitTap(), "Start Cardio")
        XCTAssertTrue(app.buttons["startType.other"].waitTap(), "Other type")
        // Other Cardio entry (feedback batch 6): GPS off → indoor recorder.
        XCTAssertTrue(app.buttons["otherCardio.start"].waitTap(), "Other Cardio Start")

        XCTAssertTrue(app.staticTexts["record.elapsed"].waitForExistence(timeout: 25), "recording")
        let hr = app.staticTexts["record.hr"]
        XCTAssertTrue(hr.waitForExistence(timeout: 10), "HR metric should be visible")
    }

    // FR-2.3 / 5.3 — a synced cardio workout's summary shows its HR chart.
    func testCardioSummaryShowsHR() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.scrollToHittableAndTap("home.train"), "open History")
        let row = app.buttons["history.cardioRow.run"]
        XCTAssertTrue(row.waitForExistence(timeout: 25), "synced run row")
        row.tap()
        XCTAssertTrue(app.otherElements["summary.hrChart"].waitForExistence(timeout: 25)
                      || app.staticTexts["Heart Rate"].waitForExistence(timeout: 15),
                      "HR chart should render in the cardio summary")
    }
}
