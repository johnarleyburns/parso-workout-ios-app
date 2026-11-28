import Foundation

/// The compact This Week band: a smaller gauge on the left, two left-justified
/// rows on the right. Values reuse the ring's own display text ("12/16 sets").
public enum ThisWeekLegendKind: String, Equatable, Sendable {
    case strength
    case cardio
}

public struct ThisWeekLegendRow: Equatable, Sendable, Identifiable {
    public let kind: ThisWeekLegendKind
    public let value: String

    public var id: String { kind.rawValue }
    public var accessibilityIdentifier: String { "home.thisWeek.\(kind.rawValue)" }
}

public enum ThisWeekCompactPresentation {
    /// Deliberately much smaller than the previous 148 pt full-size gauge.
    public static let ringDiameter: Double = 96

    public static func rows(from display: WeeklyIntentDisplay) -> [ThisWeekLegendRow] {
        [ThisWeekLegendRow(kind: .strength, value: display.strengthRing.valueText),
         ThisWeekLegendRow(kind: .cardio, value: display.cardioRing.valueText)]
    }
}
