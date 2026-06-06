import XCTest

/// UI tests for FR-6 migration & export. Run on iPhone and iPad.
final class FR6MigrationUITests: CadenceUITestCase {

    // FR-6.1 — import a Gmail-style draft and see it land in history.
    func testImportGmailDraft() {
        let app = XCUIApplication.launched()
        app.goToTab("Settings")
        XCTAssertTrue(app.scrollToAndTapButton("settings.import"), "open Import")

        app.buttons["import.sample"].waitTap()
        app.buttons["import.parse"].waitTap()
        XCTAssertTrue(app.staticTexts["import.preview"].waitForExistence(timeout: 10),
                      "parse preview should appear")
        app.buttons["import.confirm"].waitTap()
        XCTAssertTrue(app.staticTexts["import.done"].waitForExistence(timeout: 10),
                      "import should report success")

        // The imported sessions should now be in Train history.
        app.goToTab("Train")
        XCTAssertTrue(app.staticTexts["Push Day"].waitForExistence(timeout: 10),
                      "imported session should appear in history")
    }

    // FR-6.2 — export preview renders and switches format.
    func testExportPreviewAndFormat() {
        let app = XCUIApplication.launched(seeds: ["history"])
        app.goToTab("Settings")
        XCTAssertTrue(app.scrollToAndTapButton("settings.export"), "open Export")

        let preview = app.staticTexts["export.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "export preview should render")
        // Switch to CSV; the preview should contain the CSV header.
        app.buttons["CSV"].waitTap()
        let csv = app.staticTexts["export.preview"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", "session_id"), evaluatedWith: csv)
        waitForExpectations(timeout: 8)
    }
}
