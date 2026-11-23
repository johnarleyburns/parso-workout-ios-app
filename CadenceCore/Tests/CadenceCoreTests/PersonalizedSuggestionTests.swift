#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

@MainActor
struct PersonalizedSuggestionTests {
    @Test func namedOlympicMovementsStayOlympicWhenImportedCategoryIsBroad() throws {
        #expect(ExerciseTrainingType.isOlympicOnlyMovement(named: "Clean and Press"))
        #expect(ExerciseTrainingType.isOlympicOnlyMovement(named: "Clean & Jerk"))
        #expect(ExerciseTrainingType.isOlympicOnlyMovement(named: "Power Snatch"))

        let cleanAndPress = try #require(
            ImportedExerciseLibrary.templates.first { $0.name == "Clean and Press" })
        #expect(cleanAndPress.trainingTypes.contains(.olympicWeightlifting))
    }

    @Test func olympicMovementsAreNotFitnessFallbacks() {
        let cleanAndJerk = SuggestedExerciseCandidate(
            id: "clean-jerk", name: "Clean and Jerk", mechanics: .compound,
            primaryMuscles: ["quads", "glutes", "delts"],
            trainingTypes: [.olympicWeightlifting])
        let cleanAndPress = SuggestedExerciseCandidate(
            id: "clean-press", name: "Clean and Press", mechanics: .compound,
            primaryMuscles: ["quads", "glutes", "delts"],
            trainingTypes: [.olympicWeightlifting])
        let snatch = SuggestedExerciseCandidate(
            id: "snatch", name: "Snatch", mechanics: .compound,
            primaryMuscles: ["quads", "glutes", "delts"],
            trainingTypes: [.olympicWeightlifting])
        let squat = SuggestedExerciseCandidate(
            id: "squat", name: "Back Squat", mechanics: .compound,
            primaryMuscles: ["quads"], trainingTypes: [.strength])

        let bundle = SuggestedWorkoutGenerator.generate(input: SuggestedWorkoutInput(
            completedSetsByMuscle: [:],
            candidates: [cleanAndJerk, cleanAndPress, snatch, squat],
            trackedGroups: [.quadriceps, .glutes, .shoulders],
            preferredSetsPerExercise: 3,
            trainingGoal: .hypertrophy))

        let fitnessNames = Set(bundle.option(SuggestedWorkoutStyle.fitness).exercises.map { $0.name })
        #expect(!fitnessNames.contains("Clean and Jerk"))
        #expect(!fitnessNames.contains("Clean and Press"))
        #expect(!fitnessNames.contains("Snatch"))
        #expect(bundle.option(SuggestedWorkoutStyle.olympic).exercises.contains {
            ["Clean and Jerk", "Clean and Press", "Snatch"].contains($0.name)
        })
    }

    @Test func personalizedIsDisabledBelowFiveWorkouts() {
        let input = SuggestedWorkoutInput(
            completedSetsByMuscle: [:],
            candidates: [SuggestedExerciseCandidate(
                id: "bench", name: "Bench Press", mechanics: .compound,
                primaryMuscles: ["chest"], isPersonalized: true)],
            historyWorkoutCount: 4,
            historyWorkingSetCount: 20,
            trackedGroups: [.chest],
            preferredSetsPerExercise: 3,
            trainingGoal: .hypertrophy)

        let option = SuggestedWorkoutGenerator.generate(input: input).option(.personalized)
        #expect(!option.isLaunchable)
    }

    @Test func personalizedUsesOnlyExercisesMarkedFromHistory() {
        let historyExercise = SuggestedExerciseCandidate(
            id: "history", name: "Bench Press", mechanics: .compound,
            primaryMuscles: ["chest"], isPersonalized: true)
        let newExercise = SuggestedExerciseCandidate(
            id: "new", name: "Cable Fly", mechanics: .isolation,
            primaryMuscles: ["chest"])
        let input = SuggestedWorkoutInput(
            completedSetsByMuscle: [:],
            candidates: [historyExercise, newExercise],
            historyWorkoutCount: 5,
            historyWorkingSetCount: 20,
            trackedGroups: [.chest],
            preferredSetsPerExercise: 3,
            trainingGoal: .hypertrophy)

        let option = SuggestedWorkoutGenerator.generate(input: input).option(.personalized)
        #expect(option.isLaunchable)
        #expect(Set(option.exercises.map(\.candidateID)) == ["history"])
    }

    @Test func personalizedAvoidsTheMostRecentCompletedMovementPool() {
        let completedMovement = SuggestedExerciseCandidate(
            id: "completed-bench", name: "Bench Press", mechanics: .compound,
            primaryMuscles: ["chest"], isPersonalized: true)
        let freshMovement = SuggestedExerciseCandidate(
            id: "fresh-push-up", name: "Push-Up", mechanics: .compound,
            primaryMuscles: ["chest"])
        let input = SuggestedWorkoutInput(
            completedSetsByMuscle: [:],
            candidates: [completedMovement, freshMovement],
            historyWorkoutCount: 5,
            historyWorkingSetCount: 20,
            recentlyCompletedCandidateIDs: [completedMovement.id],
            trackedGroups: [.chest],
            preferredSetsPerExercise: 3,
            trainingGoal: .hypertrophy,
            preferredStyle: .fitness)

        let option = SuggestedWorkoutGenerator.generatePersonalized(input: input)

        #expect(option.isLaunchable)
        #expect(!option.exercises.contains { $0.candidateID == completedMovement.id },
                       "Completing a Today recommendation must not immediately recreate its movement pool")
        #expect(option.exercises.contains { $0.candidateID == freshMovement.id })
    }

    @Test func personalizedBuildsVolumeBeyondOneBroadCoverExercise() {
        let groups: [MuscleGroup] = [.chest, .lats, .quadriceps, .hamstrings]
        let broad = SuggestedExerciseCandidate(
            id: "broad", name: "Broad Compound", mechanics: .compound,
            primaryMuscles: groups.map(\.rawValue), isPersonalized: true)
        let accessory = SuggestedExerciseCandidate(
            id: "accessory", name: "Chest Accessory", mechanics: .isolation,
            primaryMuscles: [MuscleGroup.chest.rawValue], isPersonalized: true)
        let input = SuggestedWorkoutInput(
            completedSetsByMuscle: Dictionary(uniqueKeysWithValues: groups.map { ($0.rawValue, 0.0) }),
            candidates: [broad, accessory],
            historyWorkoutCount: 5,
            historyWorkingSetCount: 20,
            trackedGroups: Set(groups),
            preferredSetsPerExercise: 3,
            trainingGoal: .hypertrophy)

        let option = SuggestedWorkoutGenerator.generatePersonalized(input: input)

        // One broad compound touches every group, but three sets cannot close a
        // four-set weekly gap. The personalized session must keep adding work
        // instead of declaring every gap covered after a single exercise.
        #expect(option.exercises.count == 2)
        #expect(option.exercises.first?.candidateID == "broad")
        #expect(option.remainingDeficits["chest"] == 0)
        #expect(option.remainingDeficits["lats"] == 1)
        #expect(option.remainingDeficits["quadriceps"] == 1)
        #expect(option.remainingDeficits["hamstrings"] == 1)
    }

    @Test func personalizedFillsGapsOutsideANarrowPreferredStyle() {
        let circusBell = SuggestedExerciseCandidate(
            id: "circus-bell", name: "Circus Bell Press", mechanics: .compound,
            primaryMuscles: ["shoulders"], trainingTypes: [.strength, .strongman])
        let squat = SuggestedExerciseCandidate(
            id: "squat", name: "Back Squat", mechanics: .compound,
            primaryMuscles: ["quadriceps"], trainingTypes: [.strength])
        let row = SuggestedExerciseCandidate(
            id: "row", name: "Barbell Row", mechanics: .compound,
            primaryMuscles: ["lats"], trainingTypes: [.strength])
        let input = SuggestedWorkoutInput(
            completedSetsByMuscle: [:], candidates: [circusBell, squat, row],
            historyWorkoutCount: 5, historyWorkingSetCount: 20,
            trackedGroups: [.shoulders, .quadriceps, .lats],
            preferredSetsPerExercise: 3, trainingGoal: .hypertrophy,
            preferredStyle: .strongman)

        let option = SuggestedWorkoutGenerator.generatePersonalized(input: input)

        #expect(Set(option.exercises.map(\.candidateID)) ==
                       [circusBell.id, squat.id, row.id])
    }

    @Test func singleSuggestionReturnsOneMovementAndExcludesExistingAllocation() {
        let press = SuggestedExerciseCandidate(
            id: "press", name: "Bench Press", mechanics: .compound,
            primaryMuscles: ["chest"])
        let row = SuggestedExerciseCandidate(
            id: "row", name: "Barbell Row", mechanics: .compound,
            primaryMuscles: ["lats"])
        let input = SuggestedWorkoutInput(
            completedSetsByMuscle: [:], candidates: [press, row],
            trackedGroups: [.chest, .lats], preferredSetsPerExercise: 3,
            trainingGoal: .hypertrophy)

        let suggestion = SuggestedWorkoutGenerator.suggestSingleExercise(
            input: input, style: .fitness,
            alreadyAllocatedByMuscle: ["chest": 4],
            excludingCandidateIDs: ["press"])

        #expect(suggestion?.candidateID == "row")
        #expect(suggestion?.plannedSets == 3)
    }

    @Test func singleSuggestionKeepsFitnessFreeOfOlympicMovements() {
        let clean = SuggestedExerciseCandidate(
            id: "clean", name: "Clean and Press", mechanics: .compound,
            primaryMuscles: ["quads"], trainingTypes: [.olympicWeightlifting])
        let squat = SuggestedExerciseCandidate(
            id: "squat", name: "Back Squat", mechanics: .compound,
            primaryMuscles: ["quads"], trainingTypes: [.strength])
        let input = SuggestedWorkoutInput(
            completedSetsByMuscle: [:], candidates: [clean, squat],
            trackedGroups: [.quadriceps], preferredSetsPerExercise: 3,
            trainingGoal: .hypertrophy)

        let suggestion = SuggestedWorkoutGenerator.suggestSingleExercise(
            input: input, style: .fitness)

        #expect(suggestion?.candidateID == "squat")
    }

    @Test func historyIndexBackfillsAllExistingWorkoutsAndStableAliases() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let exercise = try WorkoutRepository.findOrCreateExercise(
            named: "Old History Movement", in: context)
        var sessions: [WorkoutSession] = []
        for index in 0..<3 {
            let session = try WorkoutRepository.createSession(
                date: Date(timeIntervalSince1970: Double(index + 1) * 86_400), in: context)
            _ = try WorkoutRepository.addSet(to: session, exercise: exercise,
                                             weightKg: 20, reps: 8, in: context)
            sessions.append(session)
        }

        let snapshot = ExerciseHistoryIndexStore.build(sessions: sessions)
        let stableKey = ExerciseSuggestionExclusionKey.forExercise(exercise)
        let legacyKey = "legacy:\(ExerciseLibrary.dedupKey(exercise.name))"
        #expect(Set(snapshot.entries.keys) == [stableKey, legacyKey])
        #expect(snapshot.entries[stableKey]?.completedWorkoutCount == 3)
        #expect(snapshot.entries[stableKey]?.completedWorkingSetCount == 3)
        #expect(try ExerciseHistoryIndexStore.personalizedExerciseKeys(
            sessions: sessions, storageURL: nil) == [stableKey, legacyKey])
    }

    @Test func historyIndexRebuildsAfterAHistoryChange() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let first = try WorkoutRepository.findOrCreateExercise(named: "First Movement", in: context)
        let second = try WorkoutRepository.findOrCreateExercise(named: "Second Movement", in: context)
        let session = try WorkoutRepository.createSession(in: context)
        _ = try WorkoutRepository.addSet(to: session, exercise: first, weightKg: 20, reps: 8, in: context)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-index-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try ExerciseHistoryIndexStore.rebuildIfNeeded(sessions: [session], storageURL: url))
        #expect(!(try ExerciseHistoryIndexStore.rebuildIfNeeded(sessions: [session], storageURL: url)))

        _ = try WorkoutRepository.addSet(to: session, exercise: second, weightKg: 20, reps: 8, in: context)
        let keys = try ExerciseHistoryIndexStore.personalizedExerciseKeys(
            sessions: [session], storageURL: url)
        #expect(keys.contains(ExerciseSuggestionExclusionKey.forExercise(second)))
    }
}
#endif
