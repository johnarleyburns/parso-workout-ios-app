import CadenceFeatures
import Foundation
import CadenceWorkoutFeatures

public struct WeeklyIntentRingDisplay: Equatable, Sendable {
    public let normalizedProgress: Double
    public let tintRole: WeeklySetTintRole
    public let valueText: String
    public let accessibilityLabel: String
    public let accessibilityValue: String

    public init(normalizedProgress: Double, tintRole: WeeklySetTintRole,
                valueText: String, accessibilityLabel: String, accessibilityValue: String) {
        self.normalizedProgress = normalizedProgress
        self.tintRole = tintRole
        self.valueText = valueText
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
    }
}

public struct WeeklyIntentDisplay: Equatable, Sendable {
    public let strengthRing: WeeklyIntentRingDisplay
    public let cardioRing: WeeklyIntentRingDisplay

    public init(strengthRing: WeeklyIntentRingDisplay, cardioRing: WeeklyIntentRingDisplay) {
        self.strengthRing = strengthRing
        self.cardioRing = cardioRing
    }
}

/// Glanceable weekly rings: strength sets (never days per week) and cardio minutes.
public enum WeeklyIntentPresenter {
    public static func make(strength: HomeDashboardState.Progress,
                            cardio: HomeDashboardState.Progress) -> WeeklyIntentDisplay {
        WeeklyIntentDisplay(
            strengthRing: ring(completed: strength.completed, target: strength.target,
                               valueText: strength.displayText,
                               label: {
                                   #if os(Linux)
                                   "Weekly strength sets"
                                   #else
                                   String(localized: "Weekly strength sets", bundle: FeatureLocalization.bundle)
                                   #endif
                               }(),
                               tint: WeeklyActivityColor.strength(strength.completed)),
            cardioRing: ring(completed: cardio.completed, target: cardio.target,
                             valueText: cardio.displayText,
                             label: {
                                 #if os(Linux)
                                 "Weekly cardio minutes"
                                 #else
                                 String(localized: "Weekly cardio minutes", bundle: FeatureLocalization.bundle)
                                 #endif
                             }(),
                             tint: WeeklyActivityColor.cardio(cardio.completed)))
    }

    private static func ring(completed: Double, target: Double, valueText: String,
                             label: String, tint: WeeklySetTintRole) -> WeeklyIntentRingDisplay {
        let raw = target > 0 ? completed / target : 0
        let normalized = raw.isFinite ? min(max(raw, 0), 1) : 0
        return WeeklyIntentRingDisplay(normalizedProgress: normalized, tintRole: tint,
                                       valueText: valueText, accessibilityLabel: label,
                                       accessibilityValue: valueText)
    }
}
