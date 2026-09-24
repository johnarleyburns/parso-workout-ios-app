import Foundation

/// The single progress question summarized at the top of the Progress tab.
public enum ProgressQuestion: String, CaseIterable, Sendable, Identifiable {
    case consistency
    case exerciseProgression
    case muscleVolume
    case cardioChange
    case strengthOverTime
    case tests
    case trends
    case intensity
    case effort
    case frequency

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cardioChange: return "Cardio"
        case .consistency: return "Consistency"
        case .effort: return "Effort"
        case .exerciseProgression: return "Exercise"
        case .frequency: return "Frequency"
        case .intensity: return "Intensity"
        case .muscleVolume: return "Muscle volume"
        case .strengthOverTime: return "Strength over time"
        case .tests: return "Tests"
        case .trends: return "Trends"
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
