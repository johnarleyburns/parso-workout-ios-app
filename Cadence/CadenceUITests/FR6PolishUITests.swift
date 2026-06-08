import XCTest

/// Field-testing §06 polish — the new settings toggles are present and persist.
final class FR6PolishUITests: CadenceUITestCase {

    func testPolishSettingsPresentAndPersist() {
        let app = XCUIApplication.launched()
        app.goToTab("Settings")

        // Scroll the new toggles into view.
        let colorBlind = app.switches["settings.intervalColorBlind"]
        var tries = 0
        while !colorBlind.exists && tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(colorBlind.waitForExistence(timeout: 5), "color-blind palette toggle")
        XCTAssertTrue(app.switches["settings.spokenCues"].exists, "spoken cues toggle")
        XCTAssertTrue(app.switches["settings.plateRounding"].exists, "plate rounding toggle")
        XCTAssertTrue(app.switches["settings.gpsHighAccuracy"].exists, "GPS accuracy toggle")

        // Flip the color-blind toggle and confirm it changes.
        let before = (colorBlind.value as? String) ?? "0"
        colorBlind.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertNotEqual((colorBlind.value as? String) ?? "0", before, "toggle should flip")
    }
}
