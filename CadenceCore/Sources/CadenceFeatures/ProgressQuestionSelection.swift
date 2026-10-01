import Foundation

/// The single progress question summarized at the top of the Progress tab.
public enum ProgressQuestion: String, CaseIterable, Sendable, Identifiable {
    case consistency
    case strengthOverTime
    case tests
    case personalRecords
    case intensity
    case effort
    case workoutHistory

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .consistency: return String(localized: "Consistency", bundle: .module)
        case .effort: return String(localized: "Effort", bundle: .module)
        case .intensity: return String(localized: "Intensity", bundle: .module)
        case .personalRecords: return String(localized: "Personal Records", bundle: .module)
        case .strengthOverTime: return String(localized: "Strength over time", bundle: .module)
        case .tests: return String(localized: "Tests", bundle: .module)
        case .workoutHistory: return String(localized: "Workout History", bundle: .module)
        }
    }

    public static var alphabetical: [ProgressQuestion] {
        allCases.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}

public struct ProgressQuestionSelection: Equatable, Sendable {
    public static let persistenceKey = "progress.selectedQuestion.v1"
    public private(set) var selected: ProgressQuestion

    public init(selected: ProgressQuestion = .strengthOverTime) {
        self.selected = selected
    }

    public static func persisted(defaults: UserDefaults = .standard) -> Self {
        let selected = defaults.string(forKey: persistenceKey)
            .flatMap(ProgressQuestion.init(rawValue:))
            ?? .strengthOverTime
        return Self(selected: selected)
    }

    public func persist(defaults: UserDefaults = .standard) {
        defaults.set(selected.rawValue, forKey: Self.persistenceKey)
    }

    public mutating func select(_ question: ProgressQuestion) {
        selected = question
    }
}
