import XCTest
import SwiftData
@testable import CadenceFeatures
import CadenceCore

final class WatchSingleExerciseSuggestionContextBuilderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    private func store() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    @MainActor
    private func settings() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "wsescb-\(UUID().uuidString)")!)
    }

    @MainActor
    @discardableResult
    private func log(_ name: String, at date: Date, in context: ModelContext) throws -> WorkoutSession {
        let s = try WorkoutRepository.createSession(date: date, in: context)
        let e = try WorkoutRepository.findOrCreateExercise(named: name, primaryMuscles: ["chest"], in: context)
        for i in 0..<3 {
            _ = try WorkoutRepository.addSet(to: s, exercise: e, weightKg: 60, reps: 8,
                                             completedAt: date.addingTimeInterval(Double(i) * 60), in: context)
        }
        s.endedAt = date.addingTimeInterval(600)
        return s
    }

    /// Reference: the `SuggestedExerciseRequestFactory.make` inputs, step for step.
    @MainActor
    private func reference(_ context: ModelContext, _ settings: AppSettings) throws -> SuggestedWorkoutInput {
        let history = try WorkoutRepository.allSessions(context).filter { $0.countsAsStrengthHistory }
        let sets = history.reduce(0) { $0 + $1.completedOwnerWorkingSetCount }
        let keys = try ExerciseHistoryIndexStore.personalizedExerciseKeys(sessions: history, storageURL: nil)
        let persisted = try WorkoutRepository.allExercises(context).map {
            SuggestedExerciseCandidate(
                id: ExerciseSuggestionExclusionKey.forExercise($0), name: $0.name,
                mechanics: $0.mechanicsValue ?? .compound, primaryMuscles: $0.primaryMuscles,
                secondaryMuscles: $0.secondaryMuscles, equipment: $0.equipmentValue,
                volumeEligible: $0.volumeEligible, trainingTypes: $0.trainingTypes,
                modalities: $0.modalities, sportContexts: $0.sportContexts,
                isPersonalized: keys.contains(ExerciseSuggestionExclusionKey.forExercise($0)))
        }
        let candidates = SuggestedExerciseFilter.excluding(
            persisted, keys: try ExerciseSuggestionExclusionStore.activeKeys(in: context))
        let facts = TrainingFacts.make(sessions: history, now: now, goal: settings.trainingGoal,
                                       experience: settings.experienceLevel)
        let schedule = settings.coachSchedulePreferences
        return SuggestedWorkoutInput(
            completedSetsByMuscle: facts.weeklySetsByMuscle, candidates: candidates,
            historyData: sets > 0 ? TrainingEngineBridge.historyData(from: history, subjectId: "cladiron-local") : nil,
            historyWorkoutCount: history.filter { $0.completedOwnerWorkingSetCount > 0 }.count,
            historyWorkingSetCount: sets,
            recentlyCompletedCandidateIDs: RecentSuggestionExclusion.candidateIDs(
                sessions: history, candidates: candidates),
            trackedGroups: schedule.trackedMuscleGroups,
            preferredSetsPerExercise: schedule.desiredSetsPerExercise,
            mostRecentExerciseWorkingSets: RecentSuggestionExclusion.mostRecentExerciseSetCount(sessions: history),
            trainingGoal: settings.trainingGoal, preferredStyle: settings.preferredWorkoutStyle,
            engineContext: SuggestedWorkoutEngineContext(
                experience: settings.experienceLevel, schedule: schedule,
                availableEquipment: Equipment.allCases, environment: "commercial_gym", asOf: now))
    }

    @MainActor
    private func build(_ context: ModelContext, _ settings: AppSettings) throws -> WatchSingleExerciseSuggestionContext {
        try WatchSingleExerciseSuggestionContextBuilder.make(
            context: context, settings: settings, now: now, historyIndexStorageURL: nil)
    }

    @MainActor
    func testParityWithRequestFactoryInputsAndPermanentExclusion() throws {
        let context = try store(), s = settings()
        try log("Bench Press", at: now.addingTimeInterval(-86_400 * 3), in: context)
        try log("Overhead Press", at: now.addingTimeInterval(-86_400), in: context)
        let squat = try WorkoutRepository.findOrCreateExercise(named: "Squat", primaryMuscles: ["quadriceps"], in: context)
        try ExerciseSuggestionExclusionStore.setExcluded(exercise: squat, reason: .personalPreference, in: context)

        let snapshot = try build(context, s)
        let excluded = try WatchSingleExerciseSuggestionContextBuilder.permanentlyExcludedCandidateIDs(
            in: snapshot, context: context)
        let squatID = ExerciseSuggestionExclusionKey.forExercise(squat)
        XCTAssertTrue(snapshot.baseInput.candidates.map(\.id).contains(squatID))
        XCTAssertTrue(excluded.contains(squatID))

        let ref = try reference(context, s)
        let input = try XCTUnwrap(snapshot.suggestedWorkoutInput(allocated: [:], excluding: excluded))
        XCTAssertEqual(Set(input.candidates.map(\.id)), Set(ref.candidates.map(\.id)))
        XCTAssertEqual(input.recentlyCompletedCandidateIDs, ref.recentlyCompletedCandidateIDs)
        XCTAssertEqual(input.historyWorkoutCount, ref.historyWorkoutCount)
        XCTAssertEqual(input.historyWorkingSetCount, ref.historyWorkingSetCount)
        XCTAssertEqual(input.mostRecentExerciseWorkingSets, ref.mostRecentExerciseWorkingSets)
        XCTAssertEqual(input.completedSetsByMuscle, ref.completedSetsByMuscle)
        XCTAssertEqual(input.trackedGroups, ref.trackedGroups)
        XCTAssertEqual(input.historyData != nil, ref.historyData != nil)
        for style in [SuggestedWorkoutStyle.fitness, .powerlifting] {
            let a = SuggestedWorkoutGenerator.suggestSingleExercise(input: input, style: style)
            let b = SuggestedWorkoutGenerator.suggestSingleExercise(input: ref, style: style)
            XCTAssertEqual(a, b)
        }
    }

    @MainActor
    func testEmptyHistoryIsValidAndHasNoHistoryData() throws {
        let context = try store(), s = settings()
        let snapshot = try build(context, s)
        XCTAssertNil(snapshot.baseInput.historyData)
        XCTAssertEqual(snapshot.baseInput.historyWorkingSetCount, 0)
        XCTAssertFalse(snapshot.baseInput.candidates.isEmpty)
        XCTAssertNotNil(snapshot.suggestedWorkoutInput(allocated: [:], excluding: []))
    }

    @MainActor
    func testCustomCandidateIsIncludedByCanonicalKey() throws {
        let context = try store(), s = settings()
        let custom = try WorkoutRepository.findOrCreateExercise(
            named: "Zercher Hold \(UUID().uuidString.prefix(4))", primaryMuscles: ["chest"], in: context)
        let snapshot = try build(context, s)
        XCTAssertTrue(snapshot.baseInput.candidates.contains {
            $0.id == ExerciseSuggestionExclusionKey.forExercise(custom) })
    }

    @MainActor
    func testBoundsAndDeterminism() throws {
        let context = try store(), s = settings()
        for i in 0..<30 {
            try log("Bench Press", at: now.addingTimeInterval(-86_400 * Double(i + 1)), in: context)
        }
        let a = try build(context, s), b = try build(context, s)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.baseInput.historyWorkoutCount, 30)
        XCTAssertLessThanOrEqual(a.baseInput.candidates.count, WatchSingleExerciseSuggestionContextBuilder.maxCandidates)
        let ids = a.baseInput.candidates.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        let personalized = a.baseInput.candidates.map(\.isPersonalized)
        XCTAssertEqual(personalized, personalized.sorted { $0 && !$1 })
        let history = try XCTUnwrap(a.baseInput.historyData)
        XCTAssertFalse(history.isEmpty)
    }
}
