import Foundation
import Testing
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct ExerciseProgressPresenterTests {
    @Test func summaryChoosesLatestDateBestValueAndSessionCount() {
        let calendar = Calendar(identifier: .gregorian)
        let first = calendar.date(from: DateComponents(year: 2026, month: 1, day: 3))!
        let second = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let points = [
            WorkoutRepository.TrendPoint(date: second, value: 92),
            WorkoutRepository.TrendPoint(date: first, value: 100)
        ]

        let summary = ExerciseProgressPresenter.summary(points: points)

        #expect(summary.latest?.date == second)
        #expect(summary.latest?.value == 92)
        #expect(summary.best == 100)
        #expect(summary.sessionCount == 2)
    }

    @Test func summaryIsEmptyWithoutHistory() {
        let summary = ExerciseProgressPresenter.summary(points: [])

        #expect(summary.latest == nil)
        #expect(summary.best == nil)
        #expect(summary.sessionCount == 0)
    }
}
