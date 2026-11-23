import Foundation
import Testing
#if canImport(SwiftData)
import SwiftData
#endif
@testable import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

/// Pure regressions for the phone field-test batch.
struct PhoneFieldTestAuditTests {
    @Test func addedExerciseFollowsThePlanRepStructure() {
        let sets = WorkoutPlanRepSchemeOptions.templateSets(following: [8, 8, 8])
        #expect(sets.map(\.targetReps) == [8, 8, 8])
        #expect(sets.allSatisfy { $0.targetWeight == nil })
    }

    @Test func compactWorkoutDockMatchesSmallActionHeight() {
        #expect(WorkoutDockPresenter.compactTargetHeight >= 32)
        #expect(WorkoutDockPresenter.compactTargetHeight <= 40)
    }

    @Test func trainingPartnerStartsVisibleAndCanBeArchived() {
        let partner = Person(name: "Alex")
        #expect(!partner.isArchived)
        partner.isArchived = true
        #expect(partner.isArchived)
    }

    @Test func rationaleNamesEveryMuscleGroupCoveredByAnExercise() {
        let chest = SuggestedExerciseCandidate(
            id: "chest", name: "Bench Press", mechanics: .compound,
            primaryMuscles: ["chest"], secondaryMuscles: ["triceps"])
        let back = SuggestedExerciseCandidate(
            id: "back", name: "Barbell Row", mechanics: .compound,
            primaryMuscles: ["lats"], secondaryMuscles: ["biceps"])
        let input = SuggestedWorkoutInput(
            completedSetsByMuscle: [:], candidates: [chest, back],
            trackedGroups: [.chest, .lats, .triceps, .biceps],
            preferredSetsPerExercise: 3,
            trainingGoal: .hypertrophy)
        let option = SuggestedWorkoutGenerator.generatePersonalized(input: input)
        let rationale = option.rationale
        #expect(rationale?.whyWorkout.contains("Chest") == true)
        #expect(rationale?.whyWorkout.contains("Lats") == true)
        for exercise in option.exercises {
            let reason = rationale?.rationale(for: exercise.name)?.whyExercise ?? ""
            for contribution in exercise.contributions
            where contribution.plannedSetContribution > 0 {
                let group = MuscleGroup.canonical(contribution.muscleID)
                if let group {
                    #expect(reason.contains(group.displayName),
                            "\(exercise.name) rationale omitted \(group.displayName): \(reason)")
                }
            }
        }
    }
}

#if canImport(SwiftData)

@MainActor
struct PhoneFieldTestDeletedHistoryTests {
    private func container() throws -> ModelContainer {
        try CadenceStore.makeModelContainer(inMemory: true)
    }

    @Test func softDeletedSessionNoLongerCountsTowardWeeklySets() throws {
        let context = ModelContext(try container())
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
        let exercise = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: context)
        let weekStart = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let now = weekStart.addingTimeInterval(86_400)
        let session = try WorkoutRepository.createSession(
            title: "Week", date: now.addingTimeInterval(-3600), in: context)
        for _ in 0..<3 {
            _ = try WorkoutRepository.addSet(to: session, exercise: exercise,
                                             weightKg: 60, reps: 8, in: context)
        }
        let live = TrainingFacts.make(sessions: [session], now: now,
                                      goal: .hypertrophy, experience: .intermediate)
        let before = live.weeklySetsByGroup[.chest] ?? 0
        #expect(before > 0)

        try WorkoutRepository.softDeleteSession(session, in: context)
        let after = TrainingFacts.make(sessions: [session], now: now,
                                       goal: .hypertrophy, experience: .intermediate)
        #expect((after.weeklySetsByGroup[.chest] ?? 0) == 0)
    }
}
#endif
