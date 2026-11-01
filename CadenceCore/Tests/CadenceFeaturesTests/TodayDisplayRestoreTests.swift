import Testing
@testable import CadenceFeatures

@Suite struct TodayDisplayRestoreTests {
    @Test func todayWaitsForFinishedRestore() {
        #expect(!TodayDisplayRestoreState.notStarted.permitsHydration(isToday: true))
        #expect(!TodayDisplayRestoreState.restoring.permitsHydration(isToday: true))
        #expect(TodayDisplayRestoreState.finished.permitsHydration(isToday: true))
    }

    @Test func thisWeekNeverWaits() {
        #expect(TodayDisplayRestoreState.notStarted.permitsHydration(isToday: false))
    }

    @Test func restoreIdentityIsDayAndSurfaceOnly() {
        #expect(TodayDisplayRestoreID(dayKey: "2026-11-01", isToday: true)
                == TodayDisplayRestoreID(dayKey: "2026-11-01", isToday: true))
        #expect(TodayDisplayRestoreID(dayKey: "2026-11-01", isToday: true)
                != TodayDisplayRestoreID(dayKey: "2026-11-02", isToday: true))
    }
}
