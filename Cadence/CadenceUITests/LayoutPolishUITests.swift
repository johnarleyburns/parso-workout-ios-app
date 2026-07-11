import XCTest

/// P8 (issues 5, 6, 12) — layout fixes. Issue 12 is verifiable (equal card
/// heights); issues 5 & 6 are best-effort centering, covered here by a smoke test
/// that the tab items and Settings gear remain hittable after the appearance
/// changes (the visual centering itself is verified by screenshot on device).
final class LayoutPolishUITests: CadenceUITestCase {

    func testEffortAndFrequencyCardsEqualHeight() {
        let app = XCUIApplication.launched(seeds: ["history"])
        app.tabBars.buttons.element(boundBy: 2).tap()   // Progress
        let effort = app.descendants(matching: .any).matching(identifier: "progress.effortCard").firstMatch
        let frequency = app.descendants(matching: .any).matching(identifier: "progress.frequencyCard").firstMatch
        XCTAssertTrue(effort.waitForExistence(timeout: 10))
        for _ in 0..<8 where !frequency.exists { app.swipeUp() }
        XCTAssertTrue(frequency.waitForExistence(timeout: 5), "both cards should exist")
        // The two side-by-side cards must render at equal height (issue 12).
        XCTAssertEqual(effort.frame.height, frequency.frame.height, accuracy: 1.0,
                       "Effort and Frequency cards should be equal height")
    }

    func testTabItemsAndSettingsGearHittable() {
        let app = XCUIApplication.launched()
        // Tab items remain hittable after the UITabBarAppearance change (issue 5).
        let tabButtons = app.tabBars.buttons
        XCTAssertTrue(tabButtons.element(boundBy: 0).waitForExistence(timeout: 10))
        XCTAssertEqual(tabButtons.count, 3, "three tabs present and queryable")
        XCTAssertTrue(tabButtons.element(boundBy: 0).isHittable)
        XCTAssertTrue(tabButtons.element(boundBy: 2).isHittable)
        // Settings gear remains hittable after the frame change (issue 6).
        let gear = app.buttons["home.settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10))
        XCTAssertTrue(gear.isHittable, "Settings gear should stay hittable")
        XCTAssertTrue(app.tapToReveal("home.settings", "Settings"), "gear opens Settings")
    }
}
