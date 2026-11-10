import XCTest
import CadenceCore
import CadenceFeatures

final class ArchiveTransferPresentationTests: XCTestCase {
    func testModesNeverShowBoth() {
        let e = ArchiveFlowPresentation(mode: .exportOnly)
        XCTAssertTrue(e.showsExportControls); XCTAssertFalse(e.showsRestoreControls)
        let r = ArchiveFlowPresentation(mode: .restoreOnly)
        XCTAssertTrue(r.showsRestoreControls); XCTAssertFalse(r.showsExportControls)
    }

    func testActionModels() {
        XCTAssertTrue(ArchiveActionPresenter.historyHeaderActions.contains("Export"))
        XCTAssertFalse(ArchiveActionPresenter.settingsBackupActions.contains { $0.localizedCaseInsensitiveContains("export") })
        XCTAssertTrue(ArchiveActionPresenter.settingsBackupActions.contains { $0.localizedCaseInsensitiveContains("restore") })
    }

    func testRequestIsCompleteArchive() {
        for f in ArchiveExportFormat.allCases {
            let r = ArchiveExportRequest(format: f)
            XCTAssertEqual(r.scope, .completeArchive)
            XCTAssertNotEqual(r.scope, .visiblePage)
        }
    }

    func testPayloadMappingMatchesFormats() {
        let full = CadenceExport(sessions: [], cardio: [])
        XCTAssertEqual(ArchiveExportFormat.json.payload(from: full).sessions.count, 0)
        XCTAssertTrue(ArchiveExportFormat.fit.payload(from: full).sessions.isEmpty)
        XCTAssertTrue(ArchiveExportFormat.csv.payload(from: full).cardio.isEmpty)
    }

    func testStates() {
        XCTAssertEqual(ArchiveExportState.preparing.accessibilityIdentifier, "export.loading")
        XCTAssertEqual(ArchiveExportState.failed("x").message, "x")
        XCTAssertEqual(ArchiveExportState.failed("x").accessibilityIdentifier, "export.error")
        XCTAssertNotNil(ArchiveExportState.empty.message)
        XCTAssertFalse(ArchiveExportState.empty.offersShare)
        XCTAssertTrue(ArchiveExportState.ready.offersShare)
        XCTAssertNil(ArchiveExportState.ready.message)
    }
}
