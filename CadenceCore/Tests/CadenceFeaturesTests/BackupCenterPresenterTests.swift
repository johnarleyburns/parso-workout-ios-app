import XCTest
@testable import CadenceFeatures

final class BackupCenterPresenterTests: XCTestCase {
    func testDisabledHealthExplainsWhatStaysLocal() {
        let status = BackupCenterPresenter.status(autoSaveHealth: false,
                                                   pendingHealthItems: 4,
                                                   lastHealthError: "old error")
        XCTAssertEqual(status.health, .disabled)
        XCTAssertTrue(status.healthDetail.contains("remain"))
    }

    func testErrorOutranksWaitingCount() {
        let status = BackupCenterPresenter.status(autoSaveHealth: true,
                                                   pendingHealthItems: 2,
                                                   lastHealthError: "Permission denied")
        XCTAssertEqual(status.health, .attention("Permission denied"))
        XCTAssertTrue(status.healthTitle.contains("attention"))
    }

    func testWaitingAndCurrentStates() {
        XCTAssertEqual(
            BackupCenterPresenter.status(autoSaveHealth: true, pendingHealthItems: 3, lastHealthError: nil).health,
            .waiting(3))
        XCTAssertEqual(
            BackupCenterPresenter.status(autoSaveHealth: true, pendingHealthItems: 0, lastHealthError: nil).health,
            .current)
    }

    func testRestoreSummaryNamesChangedRows() {
        let summary = BackupCenterPresenter.restoreSummary(inserted: 2, replaced: 1, skipped: 4)
        XCTAssertTrue(summary.contains("Restored 3 workouts"))
        XCTAssertTrue(summary.contains("1 newer Health version"))
        XCTAssertTrue(summary.contains("4 already current"))
    }

    func testEmptyRestoreExplainsHealthPermissionAndSync() {
        let summary = BackupCenterPresenter.restoreSummary(inserted: 0, replaced: 0, skipped: 0)
        XCTAssertTrue(summary.contains("read access"))
        XCTAssertTrue(summary.contains("syncing"))
    }
}
