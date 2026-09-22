import XCTest
@testable import CadenceFeatures

final class ProgressCardioTrendPresenterTests: XCTestCase {
    func testWeeklyTotalsIncludeOnlyCompletedNondeletedWorkoutsInEachLocalWeek() throws {
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = timeZone
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12)))
        let totals = ProgressCardioTrendPresenter.weeklyTotals(for: [], now: now, timeZone: timeZone)
        let currentWeek = try XCTUnwrap(totals.last?.start)
        let previousWeek = try XCTUnwrap(calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeek))
        let oldWeek = try XCTUnwrap(calendar.date(byAdding: .weekOfYear, value: -5, to: currentWeek))

        let workouts = [
            CardioWorkoutDurationSample(start: previousWeek.addingTimeInterval(60),
                                        end: previousWeek.addingTimeInterval(30 * 60 + 60)),
            CardioWorkoutDurationSample(start: currentWeek.addingTimeInterval(60),
                                        end: currentWeek.addingTimeInterval(45 * 60 + 60)),
            CardioWorkoutDurationSample(start: currentWeek.addingTimeInterval(120),
                                        end: currentWeek.addingTimeInterval(90 * 60 + 120), isDeleted: true),
            CardioWorkoutDurationSample(start: currentWeek.addingTimeInterval(180), end: nil),
            CardioWorkoutDurationSample(start: oldWeek.addingTimeInterval(60),
                                        end: oldWeek.addingTimeInterval(2 * 60 * 60 + 60))
        ]
        let result = ProgressCardioTrendPresenter.weeklyTotals(for: workouts, now: now, timeZone: timeZone)

        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result[result.count - 2].minutes, 30, accuracy: 0.001)
        XCTAssertEqual(result.last?.minutes ?? -1, 45, accuracy: 0.001)
        XCTAssertEqual(result.first?.minutes ?? -1, 0, accuracy: 0.001)
    }

    func testNegativeWorkoutDurationContributesZeroMinutes() throws {
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-23T12:00:00Z"))
        let totals = ProgressCardioTrendPresenter.weeklyTotals(
            for: [CardioWorkoutDurationSample(start: now, end: now.addingTimeInterval(-60))],
            now: now,
            timeZone: timeZone)

        XCTAssertEqual(totals.last?.minutes, 0)
    }
}
