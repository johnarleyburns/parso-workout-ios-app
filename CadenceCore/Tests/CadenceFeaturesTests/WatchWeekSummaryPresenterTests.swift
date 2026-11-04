import XCTest
import CadenceCore
@testable import CadenceFeatures

/// Regression for the reported defect: a successful WatchConnectivity handshake
/// rendered "0 sets / 0 min" on the Watch although iPhone This Week showed 111
/// sets and 76 cardio minutes. `WatchWeekSummaryPresenter` is the sole
/// constructor of the published `WatchSync.WeekSummary`, so this pins its exact
/// numeric mapping independent of when/why a publish is triggered.
final class WatchWeekSummaryPresenterTests: XCTestCase {
    private func row(_ sets: Double, isTracked: Bool) -> HomeDashboardState.VolumeRow {
        .init(group: .chest, displayName: "Chest", scientificName: "Pectoralis Major",
              sets: sets, zone: .productive, rangeText: "", normalized: 0,
              isTracked: isTracked, citationID: "stub")
    }

    private func dashboard(rows: [HomeDashboardState.VolumeRow], cardioMinutes: Double) -> HomeDashboardState {
        let progress = HomeDashboardState.Progress(completed: 0, target: 0, displayText: "", normalized: 0)
        let cardioDetail = HomeDashboardState.CardioDetail(
            loggedMinutes: cardioMinutes, easyMinutes: 0, moderateMinutes: cardioMinutes,
            vigorousMinutes: 0, moderateEquivalentMinutes: cardioMinutes, targetMinutes: 300,
            citationID: "stub")
        return HomeDashboardState(
            profileContext: .init(goal: "", experience: "", ageText: ""),
            strength: progress, cardio: progress, volumeCoverage: progress,
            volume: rows, cardioDetail: cardioDetail, activityDose: nil, suggestions: [])
    }

    func testExactSetsAndCardioMinutesMapThrough() {
        // Three tracked muscle rows totalling 111 sets, 76 cardio minutes.
        let state = dashboard(
            rows: [row(50, isTracked: true), row(40, isTracked: true), row(21, isTracked: true)],
            cardioMinutes: 76)

        let summary = WatchWeekSummaryPresenter.make(dashboard: state, updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(summary.sets, 111)
        XCTAssertEqual(summary.cardioMinutes, 76)
        XCTAssertEqual(summary.updatedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testSetsTargetAndMinimumUseOnlyTrackedRowsButTotalSetsIncludeEveryRow() {
        // Two tracked rows (target 24) plus one untracked row that still
        // contributes to the total-sets sum (existing all-row semantics).
        let state = dashboard(
            rows: [row(10, isTracked: true), row(10, isTracked: true), row(5, isTracked: false)],
            cardioMinutes: 0)

        let summary = WatchWeekSummaryPresenter.make(dashboard: state)

        XCTAssertEqual(summary.sets, 25)
        XCTAssertEqual(summary.setsTarget, 24)
        XCTAssertEqual(summary.setsMinimum, 24 / WeeklySetProgress.maximum * WeeklySetProgress.minimum)
    }

    func testUpdatedAtPassesThroughWithoutAlteringTotals() {
        let state = dashboard(rows: [row(12, isTracked: true)], cardioMinutes: 30)
        let stamp = Date(timeIntervalSince1970: 42)

        let summary = WatchWeekSummaryPresenter.make(dashboard: state, updatedAt: stamp)

        XCTAssertEqual(summary.updatedAt, stamp)
        XCTAssertEqual(summary.sets, 12)
        XCTAssertEqual(summary.cardioMinutes, 30)
    }
}
