import Foundation
import CadenceCore

/// One row of the Today start list. `.more` is rendered separately because it
/// opens the full cardio catalog instead of starting a workout.
public enum HomeStartRow: Equatable, Identifiable, Sendable {
    case choice(HomeWorkoutStartChoice)
    case more

    public var id: String {
        switch self {
        case .choice(let choice): return choice.id
        case .more: return "more"
        }
    }
}

public enum HomeStartList {
    public static let recentCardioLimit = 3

    /// Lift, the three most recently logged cardio types (deduplicated, most
    /// recent first), then More. Short histories are padded with the canonical
    /// concrete cardio types so the list is always five rows.
    public static func rows(recentCardio: [WorkoutType]) -> [HomeStartRow] {
        var picks: [WorkoutType] = []
        for type in recentCardio where type != .weights && type != .other && !picks.contains(type) {
            picks.append(type)
            if picks.count == recentCardioLimit { break }
        }
        for fallback in paddingOrder where picks.count < recentCardioLimit {
            if !picks.contains(fallback) { picks.append(fallback) }
        }
        return [.choice(.strength(.suggested))]
            + picks.map { HomeStartRow.choice(.cardio($0)) }
            + [.more]
    }

    /// Every cardio choice, alphabetically by its displayed title.
    public static func moreChoices() -> [HomeWorkoutStartChoice] {
        HomeWorkoutStartChoice.cardioChoices.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    /// Deterministic padding so a new install still shows three concrete rows.
    public static let paddingOrder: [WorkoutType] = [
        .hiit, .run, .cycle, .walk, .rowing, .swim, .elliptical, .stairClimber, .boxing
    ]
}
