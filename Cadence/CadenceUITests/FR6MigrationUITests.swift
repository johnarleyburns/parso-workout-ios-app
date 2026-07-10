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
        XCTAssertTrue(app.staticTexts["import.preview"].waitForExistence(timeout: 25),
                      "parse preview should appear")
        app.buttons["import.confirm"].waitTap()
        XCTAssertTrue(app.staticTexts["import.done"].waitForExistence(timeout: 25),
                      "import should report success")

        // The imported sessions should now be in Train history.
        app.goToTab("Train")
        XCTAssertTrue(app.staticTexts["Push Day"].waitForExistence(timeout: 25),
                      "imported session should appear in history")
    }

    // FR-6.2 — export summary renders and switches format without blocking the UI.
    func testExportSummaryAndFormat() {
        let app = XCUIApplication.launched(seeds: ["history"])
        app.goToTab("Settings")
        XCTAssertTrue(app.scrollToAndTapButton("settings.export"), "open Export")

        let summary = app.descendants(matching: .any)["export.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10),
                      "export summary should render quickly (no payload layout on main)")
        // The share control (URL-based) must be present with seeded data.
        XCTAssertTrue(app.buttons["export.share"].waitForExistence(timeout: 10),
                      "share link to the export file should appear")
        // Switch to CSV; the summary should still render.
        app.buttons["CSV"].waitTap()
        XCTAssertTrue(app.descendants(matching: .any)["export.summary"].waitForExistence(timeout: 10),
                      "CSV summary should render")
    }

    /// Export with seeded history must show a non-empty summary, not the empty state.
    func testExportShowsActualDataWhenHistorySeeded() {
        let app = XCUIApplication.launched(seeds: ["history"])
        app.goToTab("Settings")
        XCTAssertTrue(app.scrollToAndTapButton("settings.export"), "open Export")

        let summary = app.descendants(matching: .any)["export.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "export summary should render")
        // Seeded history offers a shareable export file and a "Strength" summary row.
        XCTAssertTrue(app.buttons["export.share"].waitForExistence(timeout: 10),
                      "seeded history must offer a shareable export file")
        XCTAssertTrue(app.staticTexts["Strength"].exists,
                      "summary card must include a Strength row for seeded history")
    }

    /// Export with no data shows the empty-state message, not an error.
    func testExportShowsEmptyStateWhenNoData() {
        let app = XCUIApplication.launched()
        app.goToTab("Settings")
        XCTAssertTrue(app.scrollToAndTapButton("settings.export"), "open Export")

        let summary = app.descendants(matching: .any)["export.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "export summary should render")
        XCTAssertTrue(summary.label.contains("No data to export"),
                      "Empty export must show the empty-state message")
    }

    /// Export with mixed history seed summarizes both strength and cardio data.
    func testExportIncludesBothStrengthAndCardioWhenMixedSeeded() {
        let app = XCUIApplication.launched(seeds: ["historyMixed"])
        app.goToTab("Settings")
        XCTAssertTrue(app.scrollToAndTapButton("settings.export"), "open Export")

        let summary = app.descendants(matching: .any)["export.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "export summary should render")
        // Mixed seed includes both strength + cardio — both rows surface in the card.
        XCTAssertTrue(app.staticTexts["Strength"].waitForExistence(timeout: 10),
                      "Mixed export summary must show a Strength row")
        XCTAssertTrue(app.staticTexts["Cardio"].exists,
                      "Mixed export summary must show a Cardio row")
    }
}
