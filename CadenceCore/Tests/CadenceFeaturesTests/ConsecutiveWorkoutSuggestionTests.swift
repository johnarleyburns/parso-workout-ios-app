#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadencePhoneFeatures
@testable import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

struct ConsecutiveWorkoutSuggestionTests {
    private var latest: SuggestedExerciseCandidate {
        .init(id: "latest", name: "Kettlebell Sumo High Pull", mechanics: .compound,
              primaryMuscles: ["shoulders"], equipment: .kettlebell, isPersonalized: true)
    }
    private var earlier: SuggestedExerciseCandidate {
        .init(id: "earlier", name: "Shoulder Press", mechanics: .compound,
              primaryMuscles: ["shoulders"], equipment: .dumbbell, isPersonalized: true)
    }
    private var workouts: [RecentCompletedWorkoutSnapshot] {
        // The last session can be arbitrarily old. Only its successor matters.
        [.init(startedAt: Date(timeIntervalSince1970: 100), endedAt: Date(timeIntervalSince1970: 200),
               exerciseNames: [earlier.name]),
         .init(startedAt: Date(timeIntervalSince1970: 300), endedAt: Date(timeIntervalSince1970: 400),
               exerciseNames: [latest.name])]
    }
    private func input(completed: Double = 0, engine: Bool = false) -> SuggestedWorkoutInput {
        .init(completedSetsByMuscle: ["shoulders": completed], candidates: [latest, earlier],
              historyWorkoutCount: 5, historyWorkingSetCount: 20,
              recentlyCompletedCandidateIDs: RecentSuggestionExclusion.candidateIDs(
                from: workouts, candidates: [latest, earlier]),
              trackedGroups: [.shoulders], preferredSetsPerExercise: 3, trainingGoal: .hypertrophy,
              preferredStyle: .fitness,
              engineContext: engine ? .init(experience: .intermediate, schedule: .default,
                availableEquipment: Equipment.allCases, environment: "commercial_gym",
                asOf: Date(timeIntervalSince1970: 900_000)) : nil)
    }

    @Test func initialBuildersExcludeOnlyLastWorkoutIncludingEnginePath() {
        for engine in [false, true] {
            let request = input(engine: engine)
            for option in SuggestedWorkoutGenerator.generate(input: request).options {
                #expect(!option.exercises.contains { $0.candidateID == latest.id }, "\(option.style)")
            }
            let personalized = SuggestedWorkoutGenerator.generatePersonalized(input: request)
            #expect(personalized.isLaunchable)
            #expect(personalized.exercises.map(\.candidateID) == [earlier.id])
        }
    }

    @Test func inWorkoutSuggestionAllowsPenultimateAndRejectsLastForEveryStyle() {
        for style in SuggestedWorkoutStyle.allCases {
            let result = SuggestedWorkoutGenerator.suggestSingleExercise(
                input: input(), style: style, allowPersonalizedFallback: true)
            #expect(result?.candidateID != latest.id, "\(style)")
            if style == .fitness || style == .personalized {
                #expect(result?.candidateID == earlier.id)
            }
        }
    }

    @Test func maintenanceAndStyleFallbackCannotReintroduceLastWorkout() {
        for completed in [0.0, 4, 30] {
            let result = SuggestedWorkoutGenerator.suggestSingleExercise(
                input: input(completed: completed), style: .personalized, allowPersonalizedFallback: true)
            #expect(result?.candidateID == earlier.id)
            #expect(SuggestedWorkoutGenerator.suggestSingleExercise(
                input: input(completed: completed), style: .personalized,
                excludingCandidateIDs: [earlier.id], allowPersonalizedFallback: true) == nil)
        }
    }

    @Test func latestAliasExcludesCanonicalCandidateWithoutBanningOlderSession() throws {
        let squat = try #require(ExerciseLibrary.template(matching: "Air Squat"))
        let candidates = [SuggestedExerciseCandidate(template: squat), earlier]
        let history = [.init(startedAt: Date(timeIntervalSince1970: 100), endedAt: Date(timeIntervalSince1970: 200),
                             exerciseNames: [earlier.name]),
                       RecentCompletedWorkoutSnapshot(startedAt: Date(timeIntervalSince1970: 300),
                             endedAt: Date(timeIntervalSince1970: 400), exerciseNames: [" Bodyweight Squat "])]
        #expect(RecentSuggestionExclusion.candidateIDs(from: history, candidates: candidates) == [candidates[0].id])
    }

    @Test func engineCannotReintroduceAnExcludedCatalogExercise() throws {
        let candidates = ExerciseLibrary.starter.map { SuggestedExerciseCandidate(template: $0) }
        func request(_ excluded: Set<String>) -> SuggestedWorkoutInput {
            .init(completedSetsByMuscle: [:], candidates: candidates,
                  recentlyCompletedCandidateIDs: excluded, trackedGroups: [.chest, .shoulders, .triceps],
                  preferredSetsPerExercise: 3, trainingGoal: .hypertrophy,
                  engineContext: .init(experience: .intermediate, schedule: .default,
                      availableEquipment: Equipment.allCases, environment: "commercial_gym",
                      asOf: Date(timeIntervalSince1970: 1_780_000_000)))
        }
        let first = try #require(SuggestedWorkoutGenerator.generate(input: request([])).option(.fitness).exercises.first)
        let excluded = RecentSuggestionExclusion.candidateIDs(
            from: [.init(startedAt: Date(timeIntervalSince1970: 100), endedAt: Date(timeIntervalSince1970: 200),
                         exerciseNames: [first.name])], candidates: candidates)
        #expect(!excluded.isEmpty)
        let next = SuggestedWorkoutGenerator.generate(input: request(excluded))
        let key = ExerciseSuggestionExclusionKey.forName(first.name)
        for option in next.options {
            #expect(!option.exercises.contains { ExerciseSuggestionExclusionKey.forName($0.name) == key }, "\(option.style)")
        }
    }

    @MainActor
    @Test func persistedHistorySkipsCurrentDeletedAndEmptySessions() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        func session(_ date: TimeInterval, name: String) throws -> WorkoutSession {
            let value = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: date), in: context)
            let exercise = try WorkoutRepository.findOrCreateExercise(named: name, primaryMuscles: ["shoulders"], in: context)
            _ = try WorkoutRepository.addSet(to: value, exercise: exercise, weightKg: 20, reps: 8,
                                             completedAt: Date(timeIntervalSince1970: date + 30), in: context)
            value.endedAt = Date(timeIntervalSince1970: date + 60)
            return value
        }
        let previous = try session(100, name: earlier.name)
        let last = try session(300, name: latest.name)
        let deleted = try session(500, name: earlier.name)
        deleted.deletedAt = Date(timeIntervalSince1970: 600)
        let empty = try WorkoutRepository.createSession(date: Date(timeIntervalSince1970: 700), in: context)
        empty.endedAt = Date(timeIntervalSince1970: 800)
        let current = try session(900, name: earlier.name)
        current.endedAt = nil
        let ids = RecentSuggestionExclusion.candidateIDs(sessions: [current, empty, deleted, last, previous],
                    excludingSessionID: current.id, candidates: [latest, earlier])
        #expect(ids == [latest.id])
        let result = SuggestedWorkoutGenerator.suggestSingleExercise(
            input: .init(completedSetsByMuscle: [:], candidates: [latest, earlier],
                         recentlyCompletedCandidateIDs: ids, trackedGroups: [.shoulders],
                         preferredSetsPerExercise: 3, trainingGoal: .hypertrophy), style: .fitness)
        #expect(result?.candidateID == earlier.id)
    }
}
#endif
