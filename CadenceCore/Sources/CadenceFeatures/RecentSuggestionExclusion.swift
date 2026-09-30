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
}
