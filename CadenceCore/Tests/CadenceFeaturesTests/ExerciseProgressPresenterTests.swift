import XCTest
import CadenceCore
import CadenceFeatures

final class ExerciseProgressPresenterTests: XCTestCase {
    func testSummaryChoosesLatestDateBestValueAndSessionCount() {
        let calendar = Calendar(identifier: .gregorian)
        let first = calendar.date(from: DateComponents(year: 2026, month: 1, day: 3))!
        let second = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let points = [
            WorkoutRepository.TrendPoint(date: second, value: 92),
            WorkoutRepository.TrendPoint(date: first, value: 100)
        ]

        let summary = ExerciseProgressPresenter.summary(points: points)

        XCTAssertEqual(summary.latest?.date, second)
        XCTAssertEqual(summary.latest?.value, 92)
        XCTAssertEqual(summary.best, 100)
        XCTAssertEqual(summary.sessionCount, 2)
    }

    func testSummaryIsEmptyWithoutHistory() {
        let summary = ExerciseProgressPresenter.summary(points: [])

        XCTAssertNil(summary.latest)
        XCTAssertNil(summary.best)
        XCTAssertEqual(summary.sessionCount, 0)
    }
}
