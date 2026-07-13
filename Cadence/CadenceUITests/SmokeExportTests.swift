import XCTest

/// Smoke: Settings → Export builds a shareable backup file off-main. The export
/// content/summary is unit-tested (`ExportPresenter`, DataExport in CadenceCore);
/// this proves the document flow renders without the old main-thread freeze.
/// Replaces FR6MigrationUITests / FR6PolishUITests / FR9PolishUITests.
final class SmokeExportTests: CadenceUITestCase {
    func testExportProducesFile() {
        let app = XCUIApplication.launched(seeds: ["history"])
        app.goToTab("Settings")
        XCTAssertTrue(app.scrollToAndTapButton("settings.export"), "open Export")

        XCTAssertTrue(app.descendants(matching: .any)["export.summary"].waitForExistence(timeout: 15),
                      "export summary should render quickly")
        XCTAssertTrue(app.buttons["export.share"].waitForExistence(timeout: 10),
                      "seeded history should offer a shareable export file")
    }
}
