import Foundation
import Testing
@testable import CadenceCore

/// Field test 2026-08-18 issue 2. `liftSnapshots` only covers the trailing week,
/// so the coach needs an all-history top set to keep plan weights real.
struct CoachSessionRecentTopSetTests {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func perExercise(_ name: String,
                             weightKg: Double,
                             reps: Int,
                             e1rm: Double,
                             at: Date) -> StrengthEventDetails.PerExercise {
        StrengthEventDetails.PerExercise(
            exerciseID: name.lowercased(),
            exerciseName: name,
            patterns: [],
            muscleGroups: [],
            hardSetCount: 3,
            topSetWeightKg: weightKg,
            topSetReps: reps,
            bestE1RM: e1rm,
            meanRPE: 8,
            maxRPE: 9,
            reachedFailure: false,
            lastWorkingSetAt: at)
    }

    private func event(_ exercises: [StrengthEventDetails.PerExercise],
                       daysAgo: Int) -> TrainingEvent {
        let end = now.addingTimeInterval(-Double(daysAgo) * 86_400)
        return TrainingEvent(
            id: UUID(),
            start: end.addingTimeInterval(-3600),
            end: end,
            kind: .strength(StrengthEventDetails(
                exercises: exercises,
                totalHardSets: exercises.reduce(0) { $0 + $1.hardSetCount },
                duration: 3600,
                sessionEnd: end)),
            source: .appStrength,
            completion: .completed)
    }

    private func facts(_ events: [TrainingEvent]) -> CoachFacts {
        CoachFacts(
            events: events,
            recovery: .empty,
            weeklyBalance: WeeklyBalance(
                strengthDays: 0, cardioDays: 0, patternsTrained: [], muscleGroupsTrained: [],
                fractionalSets: [:], moderateMinutes: 0, vigorousMinutes: 0,
                moderateEquivalentMinutes: 0, hardDays: 0, consecutiveHardDays: 0,
                vo2maxLatest: nil, vo2maxProtocol: nil, vo2maxTrend: nil,
                readinessAvailable: false, dataCompleteness: .moderate),
            goal: .strength,
            experience: .intermediate,
            referenceDate: now,
            rolling72hCompletedEvents: [],
            rolling7dCompletedEvents: [],
            rolling28dCompletedEvents: [])
    }

    @Test func recentTopSetPrefersTheNewestEvent() {
        let f = facts([
            event([perExercise("Standing Dumbbell Upright Row", weightKg: 20, reps: 12, e1rm: 28, at: now.addingTimeInterval(-21 * 86_400))], daysAgo: 21),
            event([perExercise("Standing Dumbbell Upright Row", weightKg: 25, reps: 10, e1rm: 33, at: now.addingTimeInterval(-9 * 86_400))], daysAgo: 9),
        ])
        let top = CoachSession.recentTopSet(forExerciseNamed: "Standing Dumbbell Upright Row", facts: f)
        #expect(top?.weightKg == 25)
        #expect(top?.reps == 10)
    }

    @Test func recentTopSetMatchesByCanonicalName() {
        let f = facts([event([perExercise("bench press", weightKg: 100, reps: 5, e1rm: 116, at: now)], daysAgo: 30)])
        #expect(CoachSession.recentTopSet(forExerciseNamed: "Bench Press", facts: f)?.weightKg == 100)
    }

    @Test func recentTopSetIgnoresZeroWeightSets() {
        let f = facts([event([perExercise("Push-Up", weightKg: 0, reps: 30, e1rm: 0, at: now)], daysAgo: 3)])
        #expect(CoachSession.recentTopSet(forExerciseNamed: "Push-Up", facts: f) == nil)
    }

    @Test func recentTopSetIsNilWithNoHistory() {
        #expect(CoachSession.recentTopSet(forExerciseNamed: "Bench Press", facts: facts([])) == nil)
    }
}
