import Testing
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct BackupCenterPresenterTests {
    @Test func disabledHealthExplainsWhatStaysLocal() {
        let status = BackupCenterPresenter.status(autoSaveHealth: false,
                                                   pendingHealthItems: 4,
                                                   lastHealthError: "old error")
        #expect(status.health == .disabled)
        #expect(status.healthDetail.contains("remain"))
    }

    @Test func errorOutranksWaitingCount() {
        let status = BackupCenterPresenter.status(autoSaveHealth: true,
                                                   pendingHealthItems: 2,
                                                   lastHealthError: "Permission denied")
        #expect(status.health == .attention("Permission denied"))
        #expect(status.healthTitle.contains("attention"))
    }

    @Test func waitingAndCurrentStates() {
        #expect(
            BackupCenterPresenter.status(autoSaveHealth: true, pendingHealthItems: 3, lastHealthError: nil).health
            == .waiting(3))
        #expect(
            BackupCenterPresenter.status(autoSaveHealth: true, pendingHealthItems: 0, lastHealthError: nil).health
            == .current)
    }

    @Test func restoreSummaryNamesChangedRows() {
        let summary = BackupCenterPresenter.restoreSummary(inserted: 2, replaced: 1, skipped: 4)
        #expect(summary.contains("Restored 3 workouts"))
        #expect(summary.contains("1 newer Health version"))
        #expect(summary.contains("4 already current"))
    }

    @Test func emptyRestoreExplainsHealthPermissionAndSync() {
        let summary = BackupCenterPresenter.restoreSummary(inserted: 0, replaced: 0, skipped: 0)
        #expect(summary.contains("read access"))
        #expect(summary.contains("syncing"))
    }
}
