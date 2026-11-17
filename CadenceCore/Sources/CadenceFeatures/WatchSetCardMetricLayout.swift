import Foundation

/// Presentation policy for the two editable metrics in a Watch Set Card.
/// Kept outside SwiftUI so the no-truncation contract is testable without
/// booting a Watch simulator.
public enum WatchSetCardMetricLayout: Equatable, Sendable {
    case twoColumns
    case stacked

    /// Long numeric values must shrink before WatchUI considers truncating
    /// them. This keeps supported two-decimal pound values visible in the
    /// compact two-column card.
    public static let valueMinimumScaleFactor: CGFloat = 0.55
    public static let unitMinimumScaleFactor: CGFloat = 0.70

    public static func fields(isAccessibilitySize: Bool) -> Self {
        isAccessibilitySize ? .stacked : .twoColumns
    }

    /// The Crown's weight detent: a fixed 0.5 (either unit) so entry is a true
    /// decimal scroll rather than snapping to a plate-sized jump (field report:
    /// the former 5 lb/2.5 kg "plate step" made small corrections impossible).
    public static let weightStep: Double = 0.5

    public static func crownStep(weightFocused: Bool, nonWeighted: Bool) -> Double {
        weightFocused && !nonWeighted ? weightStep : 1
    }
}
