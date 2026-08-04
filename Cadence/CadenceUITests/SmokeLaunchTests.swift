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

    /// The core loop must actually work: start a strength workout, add an
    /// exercise, and log at least one set — "the smoke gate is a pass only when
    /// a set lands in the session" (field issue: add-set regression). The
    /// picker's Add action opens the inline editor for the fresh planned
    /// exercise; it must render even with no sets logged (cache-miss
    /// regression), and saving must land a completed set row.
    func testStrengthWorkoutLogsASet() {
        let app = XCUIApplication.launched()

        XCTAssertTrue(app.startEmptyStrengthWorkout(), "strength session did not start")

        XCTAssertTrue(app.pickExercise("Bench Press"), "could not add Bench Press from picker")

        let weightField = app.textFields["set.weightField"]
        XCTAssertTrue(weightField.waitForExistence(timeout: 10),
                      "inline set editor did not open for planned exercise (add-set regression)")
        weightField.tap()
        weightField.typeText("40")

        app.buttons["set.save"].tap()

        // The set must land as a completed row on the card.
        XCTAssertTrue(app.buttons["set.editWeight.Bench Press.1"].waitForExistence(timeout: 10),
                      "logged set row did not appear")
        app.dismissRestBar()
    }
}
