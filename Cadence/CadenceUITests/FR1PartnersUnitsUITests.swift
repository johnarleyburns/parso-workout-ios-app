import XCTest

/// Field-testing §04 UI — dual lb/kg entry and partner attribution.
final class FR1PartnersUnitsUITests: CadenceUITestCase {

    private func startWorkout(_ app: XCUIApplication) {
        app.goToTab("Train")
        XCTAssertTrue(app.buttons["train.newWorkout"].waitTap(), "New Workout")
        XCTAssertTrue(app.buttons["session.addExercise"].waitForExistence(timeout: 25), "session screen")
    }

    private func openSetEditor(_ app: XCUIApplication) {
        app.buttons["session.addExercise"].tap()
        XCTAssertTrue(app.buttons["picker.row.Bench Press"].waitTap(), "pick Bench Press")
        XCTAssertTrue(app.textFields["set.weight"].waitForExistence(timeout: 25), "set editor")
    }

    // Decision #4 — type one unit, the other auto-fills with the exact value.
    func testDualUnitAutoFill() {
        let app = XCUIApplication.launched() // default unit kg
        startWorkout(app)
        openSetEditor(app)

        let primary = app.textFields["set.weight"]      // kg
        let alt = app.textFields["set.weight.alt"]       // lb
        XCTAssertTrue(alt.exists, "second (lb) field should be present")
        primary.tap(); primary.typeText("100")

        // 100 kg ≈ 220.5 lb — the alt field should auto-fill non-empty.
        let filled = NSPredicate(format: "value != %@ AND value != %@", "", "0")
        expectation(for: filled, evaluatedWith: alt)
        waitForExpectations(timeout: 10)
    }

    // Decision #13 — a set logged for a partner is tagged and kept distinct.
    func testPartnerAttribution() {
        let app = XCUIApplication.launched()
        startWorkout(app)

        // Add a partner via the partner bar (alert text field lives under alerts).
        XCTAssertTrue(app.buttons["partner.add"].waitTap(), "add partner")
        let nameField = app.alerts.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "partner name field")
        nameField.typeText("Sam")
        app.alerts.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["partner.chip.Sam"].waitForExistence(timeout: 10),
                      "Sam should appear in the partner bar")

        // Log a set attributed to Sam via the menu picker.
        openSetEditor(app)
        app.textFields["set.weight"].tap()
        app.textFields["set.weight"].typeText("90")
        let picker = app.buttons["set.performedBy"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.tap()
        XCTAssertTrue(app.buttons["Sam"].waitTap(), "select Sam in the picker")
        app.buttons["set.save"].tap()

        // The set row should carry Sam's tag.
        XCTAssertTrue(app.staticTexts["set.performer.Sam"].waitForExistence(timeout: 25),
                      "partner-attributed set should show the partner's name")
    }
}
