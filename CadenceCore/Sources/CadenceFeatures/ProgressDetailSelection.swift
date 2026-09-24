import Foundation

/// Keeps the Progress tab's secondary detail sections focused: at most one
/// dense chart/report is expanded alongside the question-led summary.
public enum ProgressDetailSection: String, CaseIterable, Sendable, Identifiable {
    case strength
    case tests
    case personalRecords
    case intensity
    case effort

    public var id: String { rawValue }
}

public struct ProgressDetailSelection: Equatable, Sendable {
    public private(set) var selected: ProgressDetailSection?

    public init(selected: ProgressDetailSection? = nil) {
        self.selected = selected
    }

    public mutating func toggle(_ section: ProgressDetailSection) {
        selected = selected == section ? nil : section
    }
}
