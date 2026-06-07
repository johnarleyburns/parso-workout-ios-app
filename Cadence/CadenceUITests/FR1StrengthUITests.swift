import XCTest

/// UI tests for FR-1 strength logging. Run on both iPhone and iPad destinations.
final class FR1StrengthUITests: CadenceUITestCase {

    // Helper: start a new empty workout and land on the session screen.
    private func startWorkout(_ app: XCUIApplication) {
        app.goToTab("Train")
        XCTAssertTrue(app.buttons["train.newWorkout"].waitTap(), "New Workout button")
        XCTAssertTrue(app.buttons["session.addExercise"].waitForExistence(timeout: 25), "session screen")
    }

    // Helper: add an exercise by name via the picker, then save a set.
    private func addExercise(_ app: XCUIApplication, named name: String, weight: String, search: Bool = false) {
        app.buttons["session.addExercise"].tap()
        if search {
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 25))
            field.tap()
            field.typeText(name)
        }
        let row = app.buttons["picker.row.\(name)"]
        if search && !row.waitForExistence(timeout: 3) {
            app.buttons["picker.create"].tap()
        } else {
            XCTAssertTrue(row.waitTap(), "picker row \(name)")
        }
        // Set editor appears; fill weight and save.
        let weightField = app.textFields["set.weight"]
        XCTAssertTrue(weightField.waitForExistence(timeout: 25), "set editor")
        weightField.tap()
        weightField.typeText(weight)
        app.buttons["set.save"].tap()
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

        // Second set, different weight. Use clearAndType: the editor pre-fills
        // the previous set's weight, so a bare typeText would concatenate.
        app.buttons["set.add.Bench Press"].tap()
        let weightField = app.textFields["set.weight"]
        XCTAssertTrue(weightField.waitForExistence(timeout: 25))
        weightField.clearAndType("105")
        app.buttons["set.save"].tap()

        XCTAssertTrue(app.buttons["set.row.Bench Press.0"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.buttons["set.row.Bench Press.1"].waitForExistence(timeout: 25))

        // Repeat last → a third set. Skip any running rest timer first so the
        // 1 Hz timer animation doesn't stall the accessibility tree on a slow
        // simulator (the repeat itself also auto-starts a rest timer).
        if app.buttons["rest.skip"].exists { app.buttons["rest.skip"].tap() }
        app.buttons["set.repeat.Bench Press"].tap()
        if app.buttons["rest.skip"].waitForExistence(timeout: 3) { app.buttons["rest.skip"].tap() }
        XCTAssertTrue(app.buttons["set.row.Bench Press.2"].waitForExistence(timeout: 25),
                      "repeat-last should add a third set")
    }

    // FR-1.3 — last-time and PR shown inline while logging.
    func testLastTimeAndPRShown() {
        let app = XCUIApplication.launched(seeds: ["priorBench"])
        startWorkout(app)
        app.buttons["session.addExercise"].tap()
        app.buttons["picker.row.Bench Press"].waitTap()
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
        app.buttons["rest.skip"].tap()
        XCTAssertFalse(app.buttons["rest.skip"].waitForExistence(timeout: 3),
                       "rest timer should dismiss after Skip")
    }

    // FR-1.6 — create a template and start a workout from it.
    func testTemplatesCreateAndStart() {
        let app = XCUIApplication.launched()
        app.goToTab("Train")
        app.buttons["train.templates"].waitTap()
        app.buttons["templates.new"].waitTap()

        let name = app.textFields["templateEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 25))
        name.tap(); name.typeText("Push Day")

        app.buttons["templateEditor.addExercise"].tap()
        app.buttons["picker.row.Bench Press"].waitTap()
        app.buttons["templateEditor.save"].waitTap()

        // Back on the templates list, then dismiss.
        XCTAssertTrue(app.staticTexts["templateRow.Push Day"].waitForExistence(timeout: 25))
        app.buttons["Done"].tap()

        // Quick Start entry should appear and launch a titled session.
        let start = app.buttons["template.start.Push Day"]
        XCTAssertTrue(start.waitForExistence(timeout: 25), "template quick-start should appear")
        start.tap()
        XCTAssertTrue(app.navigationBars["Push Day"].waitForExistence(timeout: 25),
                      "session titled after the template should open")
    }

    // FR-1.7 — edit a set then delete it.
    func testEditAndDeleteSet() {
        let app = XCUIApplication.launched()
        startWorkout(app)
        addExercise(app, named: "Bench Press", weight: "100")

        // Edit: tap the set row, change the weight, save.
        app.buttons["set.row.Bench Press.0"].waitTap()
        let weightField = app.textFields["set.weight"]
        XCTAssertTrue(weightField.waitForExistence(timeout: 25))
        weightField.clearAndType("110")
        app.buttons["set.save"].tap()

        // Verify the edit persisted by reopening the editor.
        app.buttons["set.row.Bench Press.0"].waitTap()
        XCTAssertTrue(weightField.waitForExistence(timeout: 25))
        XCTAssertEqual((weightField.value as? String) ?? "", "110", "edited weight should persist")

        // Delete from the editor.
        app.buttons["set.delete"].waitTap()
        XCTAssertFalse(app.buttons["set.row.Bench Press.0"].waitForExistence(timeout: 3),
                       "set should be removed after delete")
    }
}
