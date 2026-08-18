import Foundation

/// Single source of truth for Cladiron's shared layout rhythm. Kept in
/// CadenceFeatures (Foundation only) so "these controls are the same height" and
/// "these surfaces share Home's spacing" are unit-tested facts, not visual
/// claims. The app maps these `Double`s to `CGFloat` at the call site.
///
/// Field test 2026-08-18 issue 3: Quick Start / Custom Workout / Coach's Workout /
/// Start Workout each carried their own hard-coded height (52/56/60/64) and font.
public enum LayoutMetrics {
    // MARK: Full-width actions

    /// Height of every primary full-width action button (Home Start Workout,
    /// Quick Start, Custom Workout, Coach's Workout, plan-editor Start Workout,
    /// Do Coach's Workout).
    public static let actionButtonHeight: Double = 56
    /// Corner radius of a full-width action button.
    public static let actionButtonCornerRadius: Double = 16
    /// Vertical gap between two stacked full-width actions.
    public static let actionButtonSpacing: Double = 12

    // MARK: Page rhythm (Home is the reference)

    /// Gap between top-level sections on a scrolling surface.
    public static let sectionSpacing: Double = 20
    /// Outer page padding.
    public static let pagePadding: Double = 16
    /// Gap between rows inside a card.
    public static let cardRowSpacing: Double = 12
    /// Gap between a card's heading and its first row.
    public static let cardHeadingSpacing: Double = 10
    /// Inner padding of a card.
    public static let cardPadding: Double = 16
}
