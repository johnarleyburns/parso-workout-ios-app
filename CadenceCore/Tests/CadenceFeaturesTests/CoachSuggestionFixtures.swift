import Foundation
@testable import CadenceCore
import CadenceFeatures

enum CoachSuggestionFixtures {
    static let asOf = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static func candidate(_ id: String, _ name: String, _ muscle: String,
                          personalized: Bool = false) -> SuggestedExerciseCandidate {
        .init(id: id, name: name, mechanics: .compound, primaryMuscles: [muscle],
              secondaryMuscles: ["triceps"], equipment: .barbell, isPersonalized: personalized)
    }

    static func request(candidates: [SuggestedExerciseCandidate],
                        recent: Set<String> = [],
                        tracked: Set<MuscleGroup> = [.chest, .lats, .quadriceps],
                        history: Data? = Data([1, 2, 3]),
                        asOf: Date = CoachSuggestionFixtures.asOf) -> CoachSuggestionRequest {
        CoachSuggestionRequest(
            input: SuggestedWorkoutInput(
                completedSetsByMuscle: ["chest": 4, "lats": 0],
                candidates: candidates,
                historyData: history,
                historyWorkoutCount: 8, historyWorkingSetCount: 60,
                recentlyCompletedCandidateIDs: recent,
                trackedGroups: tracked,
                preferredSetsPerExercise: 3,
                mostRecentExerciseWorkingSets: 4,
                trainingGoal: .hypertrophy,
                preferredStyle: .fitness,
                engineContext: SuggestedWorkoutEngineContext(
                    experience: .intermediate, availableEquipment: [.barbell, .dumbbell],
                    environment: "home", asOf: asOf)),
            unit: .pounds, warmupMinutes: 5, cooldownMinutes: 5)
    }

    static var catalog: [SuggestedExerciseCandidate] {
        [candidate("bench", "Bench Press", "chest", personalized: true),
         candidate("row", "Barbell Row", "lats", personalized: true),
         candidate("squat", "Back Squat", "quadriceps", personalized: true),
         candidate("fly", "Cable Fly", "chest"),
         candidate("pulldown", "Lat Pulldown", "lats"),
         candidate("lunge", "Walking Lunge", "quadriceps")]
    }

    static func snapshot(_ request: CoachSuggestionRequest) -> CoachSuggestionSnapshot {
        CoachSuggestionSnapshotBuilder.make(request: request, generatedAt: request.input.engineContext?.asOf ?? asOf)
    }
}
