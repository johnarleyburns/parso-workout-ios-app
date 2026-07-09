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

    // FR-6.2 — export preview renders and switches format.
    func testExportPreviewAndFormat() {
        let app = XCUIApplication.launched(seeds: ["history"])
        app.goToTab("Settings")
        XCTAssertTrue(app.scrollToAndTapButton("settings.export"), "open Export")

        let preview = app.staticTexts["export.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 25), "export preview should render")
        // Switch to CSV; the preview should contain the CSV header.
        app.buttons["CSV"].waitTap()
        let csv = app.staticTexts["export.preview"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", "session_id"), evaluatedWith: csv)
        waitForExpectations(timeout: 20)
    }

    /// Export with seeded history must show real data, not "No data to export."
    func testExportShowsActualDataWhenHistorySeeded() {
        let app = XCUIApplication.launched(seeds: ["history"])
        app.goToTab("Settings")
        XCTAssertTrue(app.scrollToAndTapButton("settings.export"), "open Export")

        let preview = app.staticTexts["export.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 25), "export preview should render")

        // With "history" seed (5 weeks of sessions), the preview must NOT say "No data."
        XCTAssertFalse(preview.label.contains("No data to export"),
                       "Export with seeded history must show actual data, not empty-state message")
        // The JSON export should contain session data.
        XCTAssertTrue(preview.label.contains("\"sessions\""),
                      "JSON export must include sessions key")
    }

    /// Export with no data shows the empty-state message, not an error.
    func testExportShowsEmptyStateWhenNoData() {
        let app = XCUIApplication.launched()
        app.goToTab("Settings")
        XCTAssertTrue(app.scrollToAndTapButton("settings.export"), "open Export")

        let preview = app.staticTexts["export.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 25), "export preview should render")

        // With no seed data, the empty-state message should appear.
        XCTAssertTrue(preview.label.contains("No data to export"),
                      "Empty export must show the empty-state message")
    }

    /// CSV format shows header row plus at least one data row with seed data.
    func testCSVFormatShowsDataRows() {
        let app = XCUIApplication.launched(seeds: ["history"])
        app.goToTab("Settings")
        XCTAssertTrue(app.scrollToAndTapButton("settings.export"), "open Export")

        // Switch to CSV.
        app.buttons["CSV"].waitTap()
        let csv = app.staticTexts["export.preview"]
        XCTAssertTrue(csv.waitForExistence(timeout: 25), "CSV preview should render")

        // CSV must have header line with session_id.
        expectation(for: NSPredicate(format: "label CONTAINS %@", "session_id"), evaluatedWith: csv)
        waitForExpectations(timeout: 20)

        // With seeded history, there must be data rows (at least one Bench Press entry).
        XCTAssertTrue(csv.label.contains("Bench Press"),
                      "CSV export with history seed must contain exercise data rows")
    }

    /// Export with mixed history seed includes both strength and cardio data.
    func testExportIncludesBothStrengthAndCardioWhenMixedSeeded() {
        let app = XCUIApplication.launched(seeds: ["historyMixed"])
        app.goToTab("Settings")
        XCTAssertTrue(app.scrollToAndTapButton("settings.export"), "open Export")

        let preview = app.staticTexts["export.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 25), "export preview should render")

        // Mixed seed includes both strength and cardio — both JSON keys must appear.
        XCTAssertTrue(preview.label.contains("\"sessions\""),
                      "Mixed export must include strength sessions key")
        XCTAssertTrue(preview.label.contains("\"cardio\""),
                      "Mixed export must include cardio key")
    }
}
