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
}
