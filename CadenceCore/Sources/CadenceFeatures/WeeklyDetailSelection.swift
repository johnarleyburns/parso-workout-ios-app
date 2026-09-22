import Foundation

/// The This Week dashboard keeps at most one detailed report expanded. The
/// selected section is UI state only; it never changes or filters workout data.
public enum WeeklyDetailMode: String, CaseIterable, Sendable, Identifiable {
    case volume
    case strength
    case cardio

    public var id: String { rawValue }
}

public struct WeeklyDetailSelection: Equatable, Sendable {
    public private(set) var selected: WeeklyDetailMode?

    public init(selected: WeeklyDetailMode? = nil) {
        self.selected = selected
    }

    /// Selecting a collapsed section expands it and collapses the prior one;
    /// selecting the open section collapses all details.
    public mutating func toggle(_ mode: WeeklyDetailMode) {
        selected = selected == mode ? nil : mode
    }

    public mutating func select(_ mode: WeeklyDetailMode) {
        selected = mode
    }
}
