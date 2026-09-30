import Foundation

/// Chooses a surface layout without making SwiftUI or device-size decisions
/// part of the feature layer. Accessibility Dynamic Type always wins over a
/// wider canvas so text is given the full available width.
public enum AdaptiveSurfaceLayout: Equatable, Sendable {
    case stacked
    case twoColumn

    public static func resolve(isRegularWidth: Bool,
                               isAccessibilitySize: Bool) -> AdaptiveSurfaceLayout {
        guard isRegularWidth, !isAccessibilitySize else { return .stacked }
        return .twoColumn
    }
}
