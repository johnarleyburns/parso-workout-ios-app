import Foundation
import Testing
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WorkoutDurationEstimatorTests {
    private func plan(setCounts: [Int],
                      warmup: Int = 0, cooldown: Int = 0) -> EditablePlan {
        EditablePlan(warmupMinutes: warmup, cooldownMinutes: cooldown,
                      exercises: setCounts.map { count in
                          EditableExercise(name: "Lift", sets: (0..<count).map { _ in
                              EditableSet(targetReps: 8, targetWeight: nil)
                          }, notes: "")
                      })
    }

    @Test func emptyPlanHasNoEstimate() {
        #expect(WorkoutDurationEstimator.estimate(
            plan: plan(setCounts: []), history: []) == nil)
    }

    @Test func defaultsIncludeWarmupRestCooldownAndTransitions() {
        let estimate = WorkoutDurationEstimator.estimate(
            plan: plan(setCounts: [2, 1], warmup: 5, cooldown: 5), history: [])
        #expect(estimate == DurationEstimate(minutes: 20, basis: .defaults))
    }

    @Test func historyUsesMedianAndClampsPace() {
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
        #expect(estimate?.basis == .history(sessionCount: 3))
        #expect(estimate?.minutes == 5)
    }
}
