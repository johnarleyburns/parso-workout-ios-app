#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore

struct WatchSingleExerciseSuggestionContextBuilderTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    private func store() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    @MainActor
    private func settings() -> AppSettings {
        AppSettings(storage: InMemoryDefaultsStore())
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
    @Test func parityWithRequestFactoryInputsAndPermanentExclusion() throws {
        let context = try store(), s = settings()
        try log("Bench Press", at: now.addingTimeInterval(-86_400 * 3), in: context)
        try log("Overhead Press", at: now.addingTimeInterval(-86_400), in: context)
        let squat = try WorkoutRepository.findOrCreateExercise(named: "Squat", primaryMuscles: ["quadriceps"], in: context)
        try ExerciseSuggestionExclusionStore.setExcluded(exercise: squat, reason: .personalPreference, in: context)

        let snapshot = try build(context, s)
        let excluded = try WatchSingleExerciseSuggestionContextBuilder.permanentlyExcludedCandidateIDs(
            in: snapshot, context: context)
        let squatID = ExerciseSuggestionExclusionKey.forExercise(squat)
        #expect(snapshot.baseInput.candidates.map(\.id).contains(squatID))
        #expect(excluded.contains(squatID))

        let ref = try reference(context, s)
        let input = try #require(snapshot.suggestedWorkoutInput(allocated: [:], excluding: excluded))
        #expect(Set(input.candidates.map(\.id)) == Set(ref.candidates.map(\.id)))
        #expect(input.recentlyCompletedCandidateIDs == ref.recentlyCompletedCandidateIDs)
        #expect(input.historyWorkoutCount == ref.historyWorkoutCount)
        #expect(input.historyWorkingSetCount == ref.historyWorkingSetCount)
        #expect(input.mostRecentExerciseWorkingSets == ref.mostRecentExerciseWorkingSets)
        #expect(input.completedSetsByMuscle == ref.completedSetsByMuscle)
        #expect(input.trackedGroups == ref.trackedGroups)
        #expect((input.historyData != nil) == (ref.historyData != nil))
        for style in [SuggestedWorkoutStyle.fitness, .powerlifting] {
            let a = SuggestedWorkoutGenerator.suggestSingleExercise(input: input, style: style)
            let b = SuggestedWorkoutGenerator.suggestSingleExercise(input: ref, style: style)
            #expect(a == b)
        }
    }

    @MainActor
    @Test func emptyHistoryIsValidAndHasNoHistoryData() throws {
        let context = try store(), s = settings()
        let snapshot = try build(context, s)
        #expect(snapshot.baseInput.historyData == nil)
        #expect(snapshot.baseInput.historyWorkingSetCount == 0)
        #expect(!snapshot.baseInput.candidates.isEmpty)
        #expect(snapshot.suggestedWorkoutInput(allocated: [:], excluding: []) != nil)
    }

    @MainActor
    @Test func customCandidateIsIncludedByCanonicalKey() throws {
        let context = try store(), s = settings()
        let custom = try WorkoutRepository.findOrCreateExercise(
            named: "Zercher Hold \(UUID().uuidString.prefix(4))", primaryMuscles: ["chest"], in: context)
        let snapshot = try build(context, s)
        #expect(snapshot.baseInput.candidates.contains {
            $0.id == ExerciseSuggestionExclusionKey.forExercise(custom) })
    }

    @MainActor
    @Test func boundsAndDeterminism() throws {
        let context = try store(), s = settings()
        for i in 0..<30 {
            try log("Bench Press", at: now.addingTimeInterval(-86_400 * Double(i + 1)), in: context)
        }
        let a = try build(context, s), b = try build(context, s)
        #expect(a == b)
        #expect(a.baseInput.historyWorkoutCount == 30)
        #expect(a.baseInput.candidates.count <= WatchSingleExerciseSuggestionContextBuilder.maxCandidates)
        let ids = a.baseInput.candidates.map(\.id)
        #expect(ids.count == Set(ids).count)
        let personalized = a.baseInput.candidates.map(\.isPersonalized)
        #expect(personalized == personalized.sorted { $0 && !$1 })
        let history = try #require(a.baseInput.historyData)
        #expect(!history.isEmpty)
    }
}
#endif
