import XCTest

final class WatchSmokeTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWatchStrengthWorkoutStartsLogsAndCompletes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTest", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.tapButton("watch.startStrength", scrollAttempts: 4),
                      "Watch launcher did not show Strength Workout")

        XCTAssertTrue(app.tapButton("watchStrength.custom"),
                      "Strength start screen did not show Custom")

        XCTAssertTrue(app.buttons["watchStrength.repPattern.12-10-8"].waitForExistence(timeout: 10),
                      "Custom setup did not show rep-pattern options")
        XCTAssertTrue(app.tapButton("watchStrength.rest.60", scrollAttempts: 3),
                      "Custom setup did not show rest options")
        XCTAssertTrue(app.tapButton("watchStrength.customStart", scrollAttempts: 4),
                      "Custom setup did not start")

        XCTAssertTrue(app.tapButton("watchStrength.addExercise"),
                      "Strength session did not start")

        XCTAssertTrue(app.textFields["watchAddExercise.search"].waitForExistence(timeout: 10),
                      "Watch exercise picker did not expose search first")
        XCTAssertTrue(app.tapButton("watchAddExercise.row.Bench Press"),
                      "Watch exercise picker did not show Bench Press")
        XCTAssertTrue(app.tapButton("watchAddExercise.previewAdd"),
                      "Watch exercise preview did not show Add")

        XCTAssertTrue(app.tapButton("watchStrength.exercise.Bench Press"),
                      "Bench Press was not planned in the watch session")

        XCTAssertTrue(app.tapButton("watchWeight.plus10"),
                      "Watch weight +10 button did not exist")
        XCTAssertTrue(app.tapButton("logSetButton", scrollAttempts: 4),
                      "Watch set logger did not open")

        XCTAssertTrue(app.tapButton("watchRest.nextSet"),
                      "Watch rest screen did not appear after logging")

        XCTAssertTrue(app.tapButton("watchStrength.exercise.Bench Press"),
                      "Bench Press did not reopen after rest")
        XCTAssertTrue(app.tapButton("watchSet.delete.1"),
                      "Watch set delete was not available")
        XCTAssertTrue(app.tapButton("lastSetButton", scrollAttempts: 4),
                      "Watch Last Set did not return to exercise list")

        XCTAssertTrue(app.tapButton("watchStrength.finish", scrollAttempts: 4),
                      "Watch strength home did not return after rest")

        XCTAssertTrue(app.tapButton("watchCooldown.skip"),
                      "Watch cooldown screen did not appear")

        XCTAssertTrue(app.staticTexts["watchSummary.saved"].waitForExistence(timeout: 10),
                      "Watch summary did not render")
        XCTAssertTrue(app.buttons["watchSummary.done"].waitForExistence(timeout: 10),
                      "Watch summary Done button did not render")
    }
}

private extension XCUIApplication {
    @MainActor
    func tapButton(_ identifier: String, timeout: TimeInterval = 10, scrollAttempts: Int = 0) -> Bool {
        let button = buttons[identifier].firstMatch
        if button.waitForExistence(timeout: timeout) {
            button.tap()
            return true
        }

        for _ in 0..<scrollAttempts {
            swipeUp()
            if button.waitForExistence(timeout: 1) {
                button.tap()
                return true
            }
        }
        return false
    }
}
