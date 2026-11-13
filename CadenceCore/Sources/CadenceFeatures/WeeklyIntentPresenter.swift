import Foundation

public struct WeeklyIntentRingDisplay: Equatable, Sendable {
    public let normalizedProgress: Double
    public let tintRole: WeeklySetTintRole
    public let valueText: String
    public let accessibilityLabel: String
    public let accessibilityValue: String
}

public struct WeeklyIntentDisplay: Equatable, Sendable {
    public let strengthRing: WeeklyIntentRingDisplay
    public let cardioRing: WeeklyIntentRingDisplay
}

/// Glanceable weekly rings: strength sets (never days per week) and cardio minutes.
public enum WeeklyIntentPresenter {
    public static func make(strength: HomeDashboardState.Progress,
                            cardio: HomeDashboardState.Progress) -> WeeklyIntentDisplay {
        WeeklyIntentDisplay(
            strengthRing: ring(completed: strength.completed, target: strength.target,
                               valueText: strength.displayText,
                               label: String(localized: "Weekly strength sets", bundle: .module)),
            cardioRing: ring(completed: cardio.completed, target: cardio.target,
                             valueText: cardio.displayText,
                             label: String(localized: "Weekly cardio minutes", bundle: .module)))
    }

    private static func ring(completed: Double, target: Double, valueText: String,
                             label: String) -> WeeklyIntentRingDisplay {
        let raw = target > 0 ? completed / target : 0
        let normalized = raw.isFinite ? min(max(raw, 0), 1) : 0
        // Same ratio cut points as WeeklyCardioProgress (minimum / target).
        let tint: WeeklySetTintRole = normalized < (WeeklyCardioProgress.minimum / WeeklyCardioProgress.target)
            ? .red : (normalized < 1 ? .yellow : .green)
        return WeeklyIntentRingDisplay(normalizedProgress: normalized, tintRole: tint,
                                       valueText: valueText, accessibilityLabel: label,
                                       accessibilityValue: valueText)
    }
}
