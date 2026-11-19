import Foundation
import Testing
@testable import CadenceCore

struct StepActivitySummaryTests {

    // MARK: - Threshold categories

    @Test func statusLowBelow4000() {
        let days: [DayActivity] = stride(from: 0, through: 6, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 3500)
        }
        let summary = StepActivitySummary(from: days)
        #expect(summary.status == .low)
    }

    @Test func statusBuildingBetween4kAnd8k() {
        let days: [DayActivity] = stride(from: 0, through: 6, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 6000)
        }
        let summary = StepActivitySummary(from: days)
        #expect(summary.status == .building)
    }

    @Test func statusOnTrackAtOrAbove8k() {
        let days: [DayActivity] = stride(from: 0, through: 6, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 9000)
        }
        let summary = StepActivitySummary(from: days)
        #expect(summary.status == .onTrack)
    }

    @Test func statusExactFloorIsBuilding() {
        let days: [DayActivity] = stride(from: 0, through: 6, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 4000)
        }
        let summary = StepActivitySummary(from: days)
        #expect(summary.status == .building)
    }

    @Test func statusExactTargetIsOnTrack() {
        let days: [DayActivity] = stride(from: 0, through: 6, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 8000)
        }
        let summary = StepActivitySummary(from: days)
        #expect(summary.status == .onTrack)
    }

    // MARK: - 7-day average

    @Test func sevenDayAverageWithFullWeek() {
        let days: [DayActivity] = stride(from: 0, through: 6, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 7000)
        }
        let summary = StepActivitySummary(from: days)
        #expect(summary.sevenDayAverageSteps == 7000.0)
    }

    @Test func sevenDayAverageWithPartialData() {
        let days: [DayActivity] = stride(from: 0, through: 2, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 3000)
        }
        let summary = StepActivitySummary(from: days)
        #expect(summary.sevenDayAverageSteps == 3000.0)
    }

    @Test func sevenDayAverageWithEmptyData() {
        let summary = StepActivitySummary(from: [])
        #expect(summary.sevenDayAverageSteps == 0.0)
        #expect(summary.todaySteps == 0)
        #expect(summary.weeklyTotalSteps == 0)
        #expect(summary.status == .low)
    }

    // MARK: - Weekly total

    @Test func weeklyTotalSteps() {
        let days: [DayActivity] = stride(from: 0, through: 6, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 7500)
        }
        let summary = StepActivitySummary(from: days)
        #expect(summary.weeklyTotalSteps == 7 * 7500)
    }

    @Test func weeklyTotalWithMoreThan7Days() {
        let days: [DayActivity] = stride(from: 0, through: 9, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 5000)
        }
        let summary = StepActivitySummary(from: days)
        #expect(summary.weeklyTotalSteps == 7 * 5000)
        #expect(summary.sevenDayAverageSteps == 5000.0)
    }

    // MARK: - Today steps

    @Test func todayStepsIsMostRecent() {
        let today = Date()
        let days: [DayActivity] = [
            DayActivity(date: today.addingTimeInterval(-3 * 86400), steps: 1000),
            DayActivity(date: today, steps: 5000),
            DayActivity(date: today.addingTimeInterval(-1 * 86400), steps: 3000),
        ]
        let summary = StepActivitySummary(from: days)
        #expect(summary.todaySteps == 5000)
    }

    // MARK: - Static constants

    @Test func staticConstants() {
        #expect(StepActivitySummary.floorDailySteps == 4_000)
        #expect(StepActivitySummary.targetDailySteps == 8_000)
        #expect(StepActivitySummary.weeklyTargetSteps == 56_000)
    }
}
