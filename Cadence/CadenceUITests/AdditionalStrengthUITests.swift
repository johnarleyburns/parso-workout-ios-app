import XCTest

/// P4 (issue 3) — tapping the "Additional strength" add-on → "Start anyway" must
/// open a real workout editor/session, not dead-end back to Home.
final class AdditionalStrengthUITests: CadenceUITestCase {

    func testAdditionalStrengthStartAnywayOpensEditor() {
        // This seed completes today's plan (strength + boxing), so the coach card
        // shows the completion state with add-on options — including "Additional
        // strength" (a warn add-on) because strength was already done today.
        let app = XCUIApplication.launched(seeds: ["coachWednesdayComplete"])
        XCTAssertTrue(app.descendants(matching: .any)["coach.card"].waitForExistence(timeout: 15))

        // Expand the extra-workout options.
        let expander = app.buttons["Choose extra workout"]
        XCTAssertTrue(expander.waitForExistence(timeout: 10), "Completion state should offer extra workouts")
        expander.tap()

        // Tap the "Additional strength" add-on.
        let addon = app.buttons["coach.addon.addon.hardStrengthWarn"]
        XCTAssertTrue(scrollToElement(addon, in: app), "Additional-strength add-on should be present")
        addon.tap()

        // Confirm "Start anyway" on the warn dialog.
        let startAnyway = app.buttons["Start anyway"]
        XCTAssertTrue(startAnyway.waitForExistence(timeout: 5), "Warn dialog should offer Start anyway")
        startAnyway.tap()

        // The workout plan editor should appear (its Start button), NOT Home.
        XCTAssertTrue(app.buttons["editor.start"].waitForExistence(timeout: 15),
                      "Start anyway must open the workout editor, not dead-end to Home")
    }

    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        if element.waitForExistence(timeout: 8) { return true }
        for _ in 0..<6 where !element.exists { app.swipeUp() }
        return element.exists
    }
}
