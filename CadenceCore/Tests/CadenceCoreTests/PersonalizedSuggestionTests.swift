import XCTest
import SwiftData
@testable import CadenceCore

@MainActor
final class PersonalizedSuggestionTests: XCTestCase {
    func testNamedOlympicMovementsStayOlympicWhenImportedCategoryIsBroad() throws {
        XCTAssertTrue(ExerciseTrainingType.isOlympicOnlyMovement(named: "Clean and Press"))
        XCTAssertTrue(ExerciseTrainingType.isOlympicOnlyMovement(named: "Clean & Jerk"))
        XCTAssertTrue(ExerciseTrainingType.isOlympicOnlyMovement(named: "Power Snatch"))

        let cleanAndPress = try XCTUnwrap(
            ImportedExerciseLibrary.templates.first { $0.name == "Clean and Press" })
        XCTAssertTrue(cleanAndPress.trainingTypes.contains(.olympicWeightlifting))
    }

    func testOlympicMovementsAreNotFitnessFallbacks() {
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
        XCTAssertFalse(fitnessNames.contains("Clean and Jerk"))
        XCTAssertFalse(fitnessNames.contains("Clean and Press"))
        XCTAssertFalse(fitnessNames.contains("Snatch"))
        XCTAssertTrue(bundle.option(SuggestedWorkoutStyle.olympic).exercises.contains {
            ["Clean and Jerk", "Clean and Press", "Snatch"].contains($0.name)
        })
    }

    func testPersonalizedIsDisabledBelowFiveWorkouts() {
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
        XCTAssertFalse(option.isLaunchable)
    }

    func testPersonalizedUsesOnlyExercisesMarkedFromHistory() {
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
        XCTAssertTrue(option.isLaunchable)
        XCTAssertEqual(Set(option.exercises.map(\.candidateID)), ["history"])
    }

    func testHistoryIndexBackfillsAllExistingWorkoutsAndStableAliases() throws {
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
        XCTAssertEqual(Set(snapshot.entries.keys), [stableKey, legacyKey])
        XCTAssertEqual(snapshot.entries[stableKey]?.completedWorkoutCount, 3)
        XCTAssertEqual(snapshot.entries[stableKey]?.completedWorkingSetCount, 3)
        XCTAssertEqual(try ExerciseHistoryIndexStore.personalizedExerciseKeys(
            sessions: sessions, storageURL: nil), [stableKey, legacyKey])
    }

    func testHistoryIndexRebuildsAfterAHistoryChange() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let first = try WorkoutRepository.findOrCreateExercise(named: "First Movement", in: context)
        let second = try WorkoutRepository.findOrCreateExercise(named: "Second Movement", in: context)
        let session = try WorkoutRepository.createSession(in: context)
        _ = try WorkoutRepository.addSet(to: session, exercise: first, weightKg: 20, reps: 8, in: context)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-index-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(try ExerciseHistoryIndexStore.rebuildIfNeeded(sessions: [session], storageURL: url))
        XCTAssertFalse(try ExerciseHistoryIndexStore.rebuildIfNeeded(sessions: [session], storageURL: url))

        _ = try WorkoutRepository.addSet(to: session, exercise: second, weightKg: 20, reps: 8, in: context)
        let keys = try ExerciseHistoryIndexStore.personalizedExerciseKeys(
            sessions: [session], storageURL: url)
        XCTAssertTrue(keys.contains(ExerciseSuggestionExclusionKey.forExercise(second)))
    }
}
