import XCTest

/// Test-pyramid smoke suite (Phase 5): ~10 XCUITests that need a real OS —
/// app boot, navigation, and the core loops. Everything else moved down to
/// headless `swift test` in CadenceFeaturesTests. This file: app boots, three
/// tabs, Home hero. Replaces P3CoachHomeUITests / LayoutPolishUITests /
/// HomeSimplificationUITests / AboutUITests.
final class SmokeLaunchTests: CadenceUITestCase {
    func testColdLaunchShowsHomeAndTabs() {
        let app = XCUIApplication.launched()

        XCTAssertTrue(app.tabBars.buttons["Workout"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons["Tests"].exists)
        XCTAssertTrue(app.tabBars.buttons["Progress"].exists)

        app.tabBars.buttons["Tests"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["tests.assessments.list"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["progress"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Workout"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 5))
    }
}
