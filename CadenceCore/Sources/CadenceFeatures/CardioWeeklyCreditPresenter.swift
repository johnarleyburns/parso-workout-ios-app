import Foundation

/// Value-only weekly cardio credit for the start-mode Cardio picker (issue
/// #619). Built from Home's already-published `HomeDashboardState.CardioDetail`
/// so the picker never aggregates, fetches, or imports anything itself.
public struct CardioWeeklyCreditDisplay: Equatable, Sendable {
    /// Stable accessibility identifiers for the weekly-credit surface.
    public enum Identifier {
        public static let surface = "cardioPicker.weeklyCredit"
        public static let ring = "cardioPicker.weeklyCredit.ring"
        public static let value = "cardioPicker.weeklyCredit.value"
    }

    /// Moderate-equivalent minutes, rounded like Home's "m of n min credit".
    public let creditedMinutes: Int
    public let targetMinutes: Int
    /// `creditedMinutes / targetMinutes`, clamped to 0…1 so the ring never
    /// overdraws while the text keeps the real numerator.
    public let normalizedProgress: Double
    public let tintRole: WeeklySetTintRole
    /// e.g. "158 of 300 min credit".
    public let visibleText: String
    /// "Cardio this week".
    public let accessibilityLabel: String
    /// e.g. "158 of 300 minutes credit".
    public let accessibilityValue: String
}

public enum CardioWeeklyCreditPresenter {
    /// Largest minute value accepted before conversion to `Int`; far beyond any
    /// real week, it only keeps a corrupt input from trapping.
    static let maximumMinutes = 1_000_000.0

    /// Pure mapping from Home's authoritative credit and active target.
    public static func make(creditedMinutes: Double, targetMinutes: Double) -> CardioWeeklyCreditDisplay {
        let credit = creditedMinutes.isFinite ? min(max(creditedMinutes, 0), maximumMinutes) : 0
        // Home displays the target as `Int(target)`. A target that is not a
        // positive whole minute after that conversion would divide by zero, so
        // the existing guideline target is the deliberate fallback.
        let target: Int
        if targetMinutes.isFinite, targetMinutes < maximumMinutes, Int(targetMinutes) >= 1 {
            target = Int(targetMinutes)
        } else {
            target = Int(WeeklyCardioProgress.target)
        }
        // Same rounding as HomeDashboardPresenter's cardio display text.
        let credited = Int(credit.rounded())
        let progress = min(1, max(0, Double(credited) / Double(target)))
        return CardioWeeklyCreditDisplay(
            creditedMinutes: credited,
            targetMinutes: target,
            normalizedProgress: progress,
            // The shared weekly cardio color policy, on the unrounded credit.
            tintRole: WeeklyCardioProgress.tintRole(for: credit),
            visibleText: String(localized: "\(credited) of \(target) min credit", bundle: .module),
            accessibilityLabel: String(localized: "Cardio this week", bundle: .module),
            accessibilityValue: String(localized: "\(credited) of \(target) minutes credit", bundle: .module))
    }

    /// Adapter from the cached Home dashboard snapshot: passes its
    /// moderate-equivalent credit and active target through unchanged.
    public static func make(detail: HomeDashboardState.CardioDetail) -> CardioWeeklyCreditDisplay {
        make(creditedMinutes: detail.moderateEquivalentMinutes, targetMinutes: detail.targetMinutes)
    }
}
