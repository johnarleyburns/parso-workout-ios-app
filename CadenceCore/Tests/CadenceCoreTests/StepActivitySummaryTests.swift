import XCTest
@testable import CadenceCore

final class StepActivitySummaryTests: XCTestCase {

    // MARK: - Threshold categories

    func testStatusLowBelow4000() {
        let days: [DayActivity] = stride(from: 0, through: 6, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 3500)
        }
        let summary = StepActivitySummary(from: days)
        XCTAssertEqual(summary.status, .low)
    }

    func testStatusBuildingBetween4kAnd8k() {
        let days: [DayActivity] = stride(from: 0, through: 6, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 6000)
        }
        let summary = StepActivitySummary(from: days)
        XCTAssertEqual(summary.status, .building)
    }

    func testStatusOnTrackAtOrAbove8k() {
        let days: [DayActivity] = stride(from: 0, through: 6, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 9000)
        }
        let summary = StepActivitySummary(from: days)
        XCTAssertEqual(summary.status, .onTrack)
    }

    func testStatusExactFloorIsBuilding() {
        let days: [DayActivity] = stride(from: 0, through: 6, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 4000)
        }
        let summary = StepActivitySummary(from: days)
        XCTAssertEqual(summary.status, .building)
    }

    func testStatusExactTargetIsOnTrack() {
        let days: [DayActivity] = stride(from: 0, through: 6, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 8000)
        }
        let summary = StepActivitySummary(from: days)
        XCTAssertEqual(summary.status, .onTrack)
    }

    // MARK: - 7-day average

    func testSevenDayAverageWithFullWeek() {
        let days: [DayActivity] = stride(from: 0, through: 6, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 7000)
        }
        let summary = StepActivitySummary(from: days)
        XCTAssertEqual(summary.sevenDayAverageSteps, 7000.0)
    }

    func testSevenDayAverageWithPartialData() {
        let days: [DayActivity] = stride(from: 0, through: 2, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 3000)
        }
        let summary = StepActivitySummary(from: days)
        XCTAssertEqual(summary.sevenDayAverageSteps, 3000.0)
    }

    func testSevenDayAverageWithEmptyData() {
        let summary = StepActivitySummary(from: [])
        XCTAssertEqual(summary.sevenDayAverageSteps, 0.0)
        XCTAssertEqual(summary.todaySteps, 0)
        XCTAssertEqual(summary.weeklyTotalSteps, 0)
        XCTAssertEqual(summary.status, .low)
    }

    // MARK: - Weekly total

    func testWeeklyTotalSteps() {
        let days: [DayActivity] = stride(from: 0, through: 6, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 7500)
        }
        let summary = StepActivitySummary(from: days)
        XCTAssertEqual(summary.weeklyTotalSteps, 7 * 7500)
    }

    func testWeeklyTotalWithMoreThan7Days() {
        let days: [DayActivity] = stride(from: 0, through: 9, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 5000)
        }
        let summary = StepActivitySummary(from: days)
        XCTAssertEqual(summary.weeklyTotalSteps, 7 * 5000)
        XCTAssertEqual(summary.sevenDayAverageSteps, 5000.0)
    }

    // MARK: - Today steps

    func testTodayStepsIsMostRecent() {
        let today = Date()
        let days: [DayActivity] = [
            DayActivity(date: today.addingTimeInterval(-3 * 86400), steps: 1000),
            DayActivity(date: today, steps: 5000),
            DayActivity(date: today.addingTimeInterval(-1 * 86400), steps: 3000),
        ]
        let summary = StepActivitySummary(from: days)
        XCTAssertEqual(summary.todaySteps, 5000)
    }

    // MARK: - Static constants

    func testStaticConstants() {
        XCTAssertEqual(StepActivitySummary.floorDailySteps, 4_000)
        XCTAssertEqual(StepActivitySummary.targetDailySteps, 8_000)
        XCTAssertEqual(StepActivitySummary.weeklyTargetSteps, 56_000)
    }
}
