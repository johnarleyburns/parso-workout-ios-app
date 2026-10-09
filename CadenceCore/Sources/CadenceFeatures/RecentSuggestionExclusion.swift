import Foundation
import CadenceCore

/// The small, ephemeral history slice used to keep an immediately repeated
/// recommendation from being generated. It deliberately carries no identity
/// or persistence fields: it is rebuilt for each suggestion request.
public struct RecentCompletedWorkoutSnapshot: Equatable, Sendable {
    public let startedAt: Date
    public let endedAt: Date?
    public let exerciseNames: [String]

    public init(startedAt: Date, endedAt: Date?, exerciseNames: [String]) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exerciseNames = exerciseNames
    }

    public var completionSortDate: Date { endedAt ?? startedAt }
}

public enum RecentSuggestionExclusion {
    /// Returns the names from only the most recently completed workout.
    /// Completion time wins over start time when both are available.
    public static func exerciseNames(
        from workouts: [RecentCompletedWorkoutSnapshot]
    ) -> Set<String> {
        guard let latest = workouts.max(by: {
            $0.completionSortDate < $1.completionSortDate
        }) else { return [] }

        return Set(latest.exerciseNames.compactMap { name in
            let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedLowercase
            return normalized.isEmpty ? nil : normalized
        })
    }
    /// Catalog identity joins aliases (e.g. renamed imported movements); unknown
    /// custom names still match by normalized name. Only the latest session is used.
    public static func candidateIDs(from workouts: [RecentCompletedWorkoutSnapshot],
                                    candidates: [SuggestedExerciseCandidate]) -> Set<String> {
        let names = exerciseNames(from: workouts)
        let identities = Set(names.map(ExerciseSuggestionExclusionKey.forName))
        return Set(candidates.filter { identities.contains(ExerciseSuggestionExclusionKey.forName($0.name)) }.map(\.id))
    }

    @MainActor
    public static func candidateIDs(sessions: [WorkoutSession], excludingSessionID: UUID? = nil,
                                    candidates: [SuggestedExerciseCandidate]) -> Set<String> {
        let workouts = sessions.filter {
            $0.id != excludingSessionID && $0.countsAsStrengthHistory && $0.completedOwnerWorkingSetCount > 0
        }.map { session in
            RecentCompletedWorkoutSnapshot(startedAt: session.date, endedAt: session.endedAt,
                exerciseNames: session.orderedSets.filter { !$0.isWarmup && $0.isOwnerSet && $0.reps > 0 }
                    .compactMap { $0.exercise?.name })
        }
        return candidateIDs(from: workouts, candidates: candidates)
    }

}
