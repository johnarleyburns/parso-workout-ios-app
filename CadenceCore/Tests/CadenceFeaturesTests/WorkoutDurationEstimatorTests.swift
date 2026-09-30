import XCTest
import CadenceCore
@testable import CadenceFeatures

final class WorkoutDurationEstimatorTests: XCTestCase {
    private func plan(setCounts: [Int],
                      warmup: Int = 0, cooldown: Int = 0) -> EditablePlan {
        EditablePlan(warmupMinutes: warmup, cooldownMinutes: cooldown,
                      exercises: setCounts.map { count in
                          EditableExercise(name: "Lift", sets: (0..<count).map { _ in
                              EditableSet(targetReps: 8, targetWeight: nil)
                          }, notes: "")
                      })
    }

    func testEmptyPlanHasNoEstimate() {
        XCTAssertNil(WorkoutDurationEstimator.estimate(
            plan: plan(setCounts: []), history: []))
    }

    func testDefaultsIncludeWarmupRestCooldownAndTransitions() {
        let estimate = WorkoutDurationEstimator.estimate(
            plan: plan(setCounts: [2, 1], warmup: 5, cooldown: 5), history: [])
        XCTAssertEqual(estimate, DurationEstimate(minutes: 20, basis: .defaults))
    }

    func testHistoryUsesMedianAndClampsPace() {
        let dates = [Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 1000),
                     Date(timeIntervalSince1970: 2000)]
        let history = dates.map { date in
            let session = WorkoutSession(title: "Lift", date: date,
                                          endedAt: date.addingTimeInterval(120))
            session.sets = [SetEntry(weight: 10, reps: 8, completedAt: date.addingTimeInterval(30)),
                            SetEntry(weight: 10, reps: 8, completedAt: date.addingTimeInterval(60))]
            return session
        }
        let estimate = WorkoutDurationEstimator.estimate(
            plan: plan(setCounts: [2]), history: history)
        XCTAssertEqual(estimate?.basis, .history(sessionCount: 3))
        XCTAssertEqual(estimate?.minutes, 5)
    }
}
