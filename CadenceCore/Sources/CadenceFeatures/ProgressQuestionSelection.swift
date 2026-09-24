import Foundation

/// The single progress question summarized at the top of the Progress tab.
public enum ProgressQuestion: String, CaseIterable, Sendable, Identifiable {
    case consistency
    case exerciseProgression
    case strengthOverTime
    case tests
    case personalRecords
    case intensity
    case effort

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .consistency: return "Consistency"
        case .effort: return "Effort"
        case .exerciseProgression: return "Exercise"
        case .intensity: return "Intensity"
        case .personalRecords: return "Personal Records"
        case .strengthOverTime: return "Strength over time"
        case .tests: return "Tests"
        }
    }

    public static var alphabetical: [ProgressQuestion] {
        allCases.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}

public struct ProgressQuestionSelection: Equatable, Sendable {
    public private(set) var selected: ProgressQuestion

    public init(selected: ProgressQuestion = .consistency) {
        self.selected = selected
    }

    public mutating func select(_ question: ProgressQuestion) {
        selected = question
    }
}
