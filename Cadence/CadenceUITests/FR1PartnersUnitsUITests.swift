import XCTest

/// Field-testing §04 UI — dual lb/kg entry and partner attribution.
final class FR1PartnersUnitsUITests: CadenceUITestCase {

    private func startWorkout(_ app: XCUIApplication) {
        XCTAssertTrue(app.startEmptyStrengthWorkout(), "session screen")
    }

    private func openSetEditor(_ app: XCUIApplication) {
        app.buttons["session.addExercise"].tap()
        XCTAssertTrue(app.buttons["picker.row.Bench Press"].waitTap(), "pick Bench Press")
        XCTAssertTrue(app.staticTexts["set.weight"].waitForExistence(timeout: 25), "weight keypad")
    }

    // Decision #4 — type one unit, the other auto-converts on the keypad read-out.
    func testDualUnitAutoFill() {
        let app = XCUIApplication.launched() // default unit kg
        startWorkout(app)
        openSetEditor(app)

        let alt = app.staticTexts["set.weight.alt"]      // lb read-out
        XCTAssertTrue(alt.waitForExistence(timeout: 5), "alt-unit read-out should be present")
        XCTAssertEqual(alt.label, "—", "alt should be blank before any weight is entered")
        app.keypadEnter("100")

        // 100 kg ≈ 220.5 lb — the alt read-out should auto-fill (no longer "—").
        let filled = NSPredicate(format: "label != %@", "—")
        expectation(for: filled, evaluatedWith: alt)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(alt.label.contains("lb"), "alt read-out should show the lb conversion")
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

        // Log a set — with partners, the active row shows the current performer.
        openSetEditor(app)
        app.recordKeypadSet("90")

        // The set row should carry Sam's tag (alternating partner rotation).
        XCTAssertTrue(app.staticTexts["set.performer.Sam"].waitForExistence(timeout: 25),
                      "partner-attributed set should show the partner's chip")
    }

    // MARK: — unified plan columnar partner tests (2026-06-22)

    func testPerformerChipsAppearInColumnarLayout() {
        let app = XCUIApplication.launched()
        startWorkout(app)
        // Add a partner
        app.buttons["partner.add"].tap()
        XCTAssertTrue(app.textFields["partner.nameField"].waitForExistence(timeout: 10))
        app.textFields["partner.nameField"].typeText("Alex\r")
        app.buttons["Add"].tap()

        // Log a set
        openSetEditor(app)
        app.recordKeypadSet("60")

        // Performer chip should appear on the set row
        // (either "M" for Me or "A" for Alex depending on rotation)
        XCTAssertTrue(app.staticTexts["set.performer.Me"].waitForExistence(timeout: 25),
                      "Set row should show performer chip")
    }

    func testAddedPartnerAppearsInEditor() {
        let app = XCUIApplication.launched(seeds: ["person.Sam"])
        // Navigate to Quick Start → Editor
        app.popToHome()
        XCTAssertTrue(app.scrollToHittableAndTap("home.startWorkout"))
        XCTAssertTrue(app.buttons["weights.quickStart"].waitTap())

        // Partner picker should show Sam
        XCTAssertTrue(app.staticTexts["editor.partner.Sam"].waitForExistence(timeout: 10),
                      "Partner picker in editor should list Sam")
    }
}
