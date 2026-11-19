import Testing
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct ArchiveTransferPresentationTests {
    @Test func modesNeverShowBoth() {
        let e = ArchiveFlowPresentation(mode: .exportOnly)
        #expect(e.showsExportControls); #expect(!e.showsRestoreControls)
        let r = ArchiveFlowPresentation(mode: .restoreOnly)
        #expect(r.showsRestoreControls); #expect(!r.showsExportControls)
    }

    @Test func actionModels() {
        #expect(ArchiveActionPresenter.historyHeaderActions.contains("Export"))
        #expect(!ArchiveActionPresenter.settingsBackupActions.contains { $0.localizedCaseInsensitiveContains("export") })
        #expect(ArchiveActionPresenter.settingsBackupActions.contains { $0.localizedCaseInsensitiveContains("restore") })
    }

    @Test func requestIsCompleteArchive() {
        for f in ArchiveExportFormat.allCases {
            let r = ArchiveExportRequest(format: f)
            #expect(r.scope == .completeArchive)
            #expect(r.scope != .visiblePage)
        }
    }

    @Test func payloadMappingMatchesFormats() {
        let full = CadenceExport(sessions: [], cardio: [])
        #expect(ArchiveExportFormat.json.payload(from: full).sessions.count == 0)
        #expect(ArchiveExportFormat.fit.payload(from: full).sessions.isEmpty)
        #expect(ArchiveExportFormat.csv.payload(from: full).cardio.isEmpty)
    }

    @Test func states() {
        #expect(ArchiveExportState.preparing.accessibilityIdentifier == "export.loading")
        #expect(ArchiveExportState.failed("x").message == "x")
        #expect(ArchiveExportState.failed("x").accessibilityIdentifier == "export.error")
        #expect(ArchiveExportState.empty.message != nil)
        #expect(!ArchiveExportState.empty.offersShare)
        #expect(ArchiveExportState.ready.offersShare)
        #expect(ArchiveExportState.ready.message == nil)
    }
}
