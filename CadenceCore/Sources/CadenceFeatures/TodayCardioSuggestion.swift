import Foundation
import CadenceCore

/// Same-day persistence for the Today "Suggested Cardio for You" card, so the
/// cached suggestion shows first on launch and a newer one is offered behind an
/// explicit "Show newer suggested workout…" link (the coach suggests, NFR-8).
public struct TodayCardioSuggestionCache: Sendable {
    private struct Envelope: Codable { var dayKey: String; var suggestion: CardioSuggestion }
    private static let key = "home.todayCardioSuggestion.v1"

    public init() {}

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    public func load(now: Date = Date(), calendar: Calendar = .current,
                     defaults: UserDefaults = .standard) -> CardioSuggestion? {
        guard let data = defaults.data(forKey: Self.key),
              let env = try? JSONDecoder().decode(Envelope.self, from: data),
              env.dayKey == Self.dayKey(now, calendar: calendar) else { return nil }
        return env.suggestion
    }

    public func save(_ suggestion: CardioSuggestion, now: Date = Date(), calendar: Calendar = .current,
                     defaults: UserDefaults = .standard) {
        let env = Envelope(dayKey: Self.dayKey(now, calendar: calendar), suggestion: suggestion)
        if let data = try? JSONEncoder().encode(env) { defaults.set(data, forKey: Self.key) }
    }
}

/// Shows a freshly computed suggestion immediately when nothing (or the same
/// thing) is displayed; otherwise holds it behind the "Show newer…" link.
public enum TodayCardioReplacementGate {
    public static func decide(displayed: CardioSuggestion?,
                              fresh: CardioSuggestion) -> TodaySuggestionReplacement {
        guard let displayed, displayed != fresh else { return .applyImmediately }
        return .holdPending
    }
}

public extension SuggestedWorkoutInput {
    /// The same request with the named exercises removed from the candidate pool,
    /// so "Suggest Another" yields a different workout. Falls back to the
    /// unchanged input when exclusion would leave nothing to choose from.
    func excludingCandidates(named names: Set<String>) -> SuggestedWorkoutInput {
        let lowered = Set(names.map { $0.lowercased() })
        let remaining = candidates.filter { !lowered.contains($0.name.lowercased()) }
        guard !remaining.isEmpty, remaining.count < candidates.count else { return self }
        return SuggestedWorkoutInput(
            completedSetsByMuscle: completedSetsByMuscle, candidates: remaining,
            historyData: historyData, historyWorkoutCount: historyWorkoutCount,
            historyWorkingSetCount: historyWorkingSetCount,
            recentlyCompletedCandidateIDs: recentlyCompletedCandidateIDs,
            trackedGroups: trackedGroups, preferredSetsPerExercise: preferredSetsPerExercise,
            mostRecentExerciseWorkingSets: mostRecentExerciseWorkingSets,
            trainingGoal: trainingGoal, preferredStyle: preferredStyle, engineContext: engineContext)
    }
}
