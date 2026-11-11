import Foundation
import CadenceCore

/// One top-level block of the Strength start surface, in render order.
public enum StrengthStartItem: Equatable, Sendable {
    case suggestWorkout
    case muscleCoverage
    case quickStart
    case previousWorkouts
    case library
    case heartRateMonitoring
}

/// Routes whose navigation title this policy owns.
public enum StrengthStartRoute: Equatable, Sendable {
    case strengthStart
    case other(String)
}

public struct StrengthStartAccessibility: Equatable, Sendable {
    public let identifier: String
    public let label: String
    public let isHeading: Bool
    /// True only when the element would contain the Suggest action.
    public let containsSuggestAction: Bool
}

/// Value-only layout policy for `WeightsStartView` (issue #620). Performs no
/// SwiftData, HealthKit or aggregation work; the view injects all data.
public enum StrengthStartLayoutPresenter {
    public static let titleKey: String.LocalizationValue = "Strength this week"

    public static func items(hasPrevious: Bool) -> [StrengthStartItem] {
        // `hasPrevious` only changes the rows inside `.previousWorkouts`.
        [.suggestWorkout, .muscleCoverage, .quickStart,
         .previousWorkouts, .library, .heartRateMonitoring]
    }

    public static func navigationTitle(for route: StrengthStartRoute) -> String {
        switch route {
        case .strengthStart: return String(localized: titleKey, bundle: .module)
        case .other(let title): return title
        }
    }

    /// The Suggest action keeps the existing strength suggestion intent.
    public static let suggestIntent: SuggestedWorkoutModality = .strength

    public static func accessibility(for item: StrengthStartItem) -> StrengthStartAccessibility? {
        switch item {
        case .suggestWorkout:
            return StrengthStartAccessibility(identifier: "weights.suggestWorkout",
                                              label: "Suggest a Workout",
                                              isHeading: false, containsSuggestAction: false)
        case .muscleCoverage:
            return StrengthStartAccessibility(identifier: "weights.muscleCoverage",
                                              label: "Muscle coverage",
                                              isHeading: true, containsSuggestAction: false)
        default:
            return nil
        }
    }
}
