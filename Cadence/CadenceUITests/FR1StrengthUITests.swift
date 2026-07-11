import XCTest

/// UI tests for FR-1 strength logging. Run on both iPhone and iPad destinations.
final class FR1StrengthUITests: CadenceUITestCase {

    // Helper: start a new empty workout and land on the session screen.
    private func startWorkout(_ app: XCUIApplication) {
        XCTAssertTrue(app.startEmptyStrengthWorkout(), "session screen")
    }

    // Helper: add an exercise by name via the picker, then save a set.
    private func addExercise(_ app: XCUIApplication, named name: String, weight: String, search: Bool = false) {
        if search {
            app.buttons["session.addExercise"].tap()
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 25))
            field.tap()
            field.typeText(name)
            let row = app.buttons["picker.row.\(name)"]
            if !row.waitForExistence(timeout: 3) {
                app.buttons["picker.create"].tap()
            } else {
                XCTAssertTrue(row.waitTap(), "picker row \(name)")
            }
        } else {
            // Tab-independent pick via search (Recents can be empty in -uiTest).
            XCTAssertTrue(app.pickExercise(name), "picker row \(name)")
        }
        // Weight keypad appears; enter the weight and Record.
        app.recordKeypadSet(weight)
    }

    // FR-1.1 — add a library exercise and a custom one.
    func testAddLibraryAndCustomExercise() {
        let app = XCUIApplication.launched()
        startWorkout(app)

        addExercise(app, named: "Bench Press", weight: "100")
        XCTAssertTrue(app.staticTexts["exerciseCard.Bench Press"].waitForExistence(timeout: 25),
                      "library exercise card should appear")

        addExercise(app, named: "Zercher Squat", weight: "60", search: true)
        XCTAssertTrue(app.staticTexts["exerciseCard.Zercher Squat"].waitForExistence(timeout: 25),
                      "custom exercise card should appear")
    }

    // FR-1.2 — multiple sets with different weights, plus repeat-last.
    func testLogMultipleSetsAndRepeat() {
        let app = XCUIApplication.launched()
        startWorkout(app)
        addExercise(app, named: "Bench Press", weight: "100")

        // Second set, different weight. A new set starts with an empty keypad entry.
        app.buttons["set.add.Bench Press"].tap()
        app.recordKeypadSet("105")

        XCTAssertTrue(app.buttons["set.row.Bench Press.0"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.buttons["set.row.Bench Press.1"].waitForExistence(timeout: 25))

        // Repeat last → a third set. Skip any running rest timer first so the
        // 1 Hz timer animation doesn't stall the accessibility tree on a slow
        // simulator (the repeat itself also auto-starts a rest timer).
        app.dismissRestBar()
        app.buttons["set.repeat.Bench Press"].tap()
        app.dismissRestBar()
        XCTAssertTrue(app.buttons["set.row.Bench Press.2"].waitForExistence(timeout: 25),
                      "repeat-last should add a third set")
    }

    // FR-1.3 — last-time and PR shown inline while logging.
    func testLastTimeAndPRShown() {
        let app = XCUIApplication.launched(seeds: ["priorBench"])
        startWorkout(app)
        XCTAssertTrue(app.pickExercise("Bench Press"), "pick Bench Press")
        // In the set editor, last-time + PR context is visible.
        XCTAssertTrue(app.staticTexts["exercise.lastTime"].waitForExistence(timeout: 25),
                      "last-time should be shown")
        XCTAssertTrue(app.staticTexts["exercise.pr"].exists, "PR should be shown")
    }

    // FR-1.4 — logging a heavier set than the prior best flags a PR.
    func testNewPRBadge() {
        let app = XCUIApplication.launched(seeds: ["priorBench"]) // prior best 100kg
        startWorkout(app)
        addExercise(app, named: "Bench Press", weight: "110") // heavier → PR
        XCTAssertTrue(app.images["set.prBadge"].waitForExistence(timeout: 25)
                      || app.staticTexts["set.prBadge"].waitForExistence(timeout: 2),
                      "a PR badge should appear for a record set")
    }

    // FR-1.5 — rest timer auto-starts and can be skipped.
    func testRestTimerAutoStartAndSkip() {
        let app = XCUIApplication.launched()
        startWorkout(app)
        addExercise(app, named: "Bench Press", weight: "100")
        XCTAssertTrue(app.otherElements["rest.bar"].waitForExistence(timeout: 25)
                      || app.buttons["rest.skip"].waitForExistence(timeout: 15),
                      "rest timer should auto-start")
        app.dismissRestBar()
        XCTAssertFalse(app.buttons["rest.skip"].waitForExistence(timeout: 3),
                       "rest timer should dismiss after Skip")
    }

    // FR-1.6 / field-testing §04 (decision #16) — templates retired in favor of
    // reusing a past workout fresh.
    func testTemplatesRemovedAndReuseWorkout() {
        let app = XCUIApplication.launched(seeds: ["priorBench"]) // a past "Push Day"
        app.goToTab("Train")
        XCTAssertFalse(app.buttons["train.templates"].exists, "Templates UI should be gone")

        let row = app.buttons["session.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 25))
        row.swipeRight()
        XCTAssertTrue(app.buttons["Reuse"].waitTap(), "Reuse swipe action")

        XCTAssertTrue(app.navigationBars["Push Day"].waitForExistence(timeout: 25),
                      "reused session opens titled after the original")
        XCTAssertTrue(app.staticTexts["exerciseCard.Bench Press"].waitForExistence(timeout: 25),
                      "reused workout pre-loads its exercises")
    }

    // FR-1.7 — edit a set then delete it.
    func testEditAndDeleteSet() {
        let app = XCUIApplication.launched()
        startWorkout(app)
        addExercise(app, named: "Bench Press", weight: "100")

        // Edit: tap the set row, clear the pre-filled weight, change it, save.
        app.buttons["set.row.Bench Press.0"].waitTap()
        app.recordKeypadSet("110", clear: true)

        // Verify the edit persisted by reopening the keypad — its big display
        // carries the entry as its accessibility value.
        app.buttons["set.row.Bench Press.0"].waitTap()
        let weightDisplay = app.staticTexts["set.weight"]
        XCTAssertTrue(weightDisplay.waitForExistence(timeout: 25))
        XCTAssertEqual((weightDisplay.value as? String) ?? "", "110", "edited weight should persist")

        // Delete from the keypad.
        app.buttons["set.delete"].waitTap()
        XCTAssertFalse(app.buttons["set.row.Bench Press.0"].waitForExistence(timeout: 3),
                       "set should be removed after delete")
    }
}
