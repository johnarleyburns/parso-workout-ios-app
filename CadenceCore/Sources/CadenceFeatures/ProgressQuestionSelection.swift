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
    case readiness

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .consistency: return String(localized: "Consistency", bundle: .module)
        case .effort: return String(localized: "Effort", bundle: .module)
        case .intensity: return String(localized: "Intensity", bundle: .module)
        case .personalRecords: return String(localized: "Personal Records", bundle: .module)
        case .strengthOverTime: return String(localized: "Strength over time", bundle: .module)
        case .tests: return String(localized: "Tests", bundle: .module)
        case .workoutHistory: return String(localized: "My Workouts", bundle: .module)
        case .readiness: return String(localized: "Readiness", bundle: .module)
        }
    }

    /// Whether the question renders its own list below the picker instead of
    /// the shared scrolling page. The picker itself is identical either way.
    public var hostsOwnList: Bool { self == .workoutHistory }

    /// My Workouts leads because it is the primary activity record; the rest
    /// remain stable rather than shifting with localization sort order.
    public static var alphabetical: [ProgressQuestion] {
        [.workoutHistory, .strengthOverTime, .personalRecords, .consistency,
         .intensity, .effort, .tests, .readiness]
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
