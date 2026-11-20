import CadenceFeatures
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
    case observations

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .consistency: return {
            #if os(Linux)
            "Consistency"
            #else
            String(localized: "Consistency", bundle: FeatureLocalization.bundle)
            #endif
        }()
        case .effort: return {
            #if os(Linux)
            "Effort"
            #else
            String(localized: "Effort", bundle: FeatureLocalization.bundle)
            #endif
        }()
        case .intensity: return {
            #if os(Linux)
            "Intensity"
            #else
            String(localized: "Intensity", bundle: FeatureLocalization.bundle)
            #endif
        }()
        case .personalRecords: return {
            #if os(Linux)
            "Personal Records"
            #else
            String(localized: "Personal Records", bundle: FeatureLocalization.bundle)
            #endif
        }()
        case .strengthOverTime: return {
            #if os(Linux)
            "Lifts"
            #else
            String(localized: "Lifts", bundle: FeatureLocalization.bundle)
            #endif
        }()
        case .tests: return {
            #if os(Linux)
            "Tests"
            #else
            String(localized: "Tests", bundle: FeatureLocalization.bundle)
            #endif
        }()
        case .workoutHistory: return {
            #if os(Linux)
            "My Workouts"
            #else
            String(localized: "My Workouts", bundle: FeatureLocalization.bundle)
            #endif
        }()
        case .readiness: return {
            #if os(Linux)
            "Readiness"
            #else
            String(localized: "Readiness", bundle: FeatureLocalization.bundle)
            #endif
        }()
        case .observations: return {
            #if os(Linux)
            "Observations"
            #else
            String(localized: "Observations", bundle: FeatureLocalization.bundle)
            #endif
        }()
        }
    }

    /// Whether the question renders its own list below the picker instead of
    /// the shared scrolling page. The picker itself is identical either way.
    public var hostsOwnList: Bool { self == .workoutHistory }

    /// The sole picker-ordering API: localized alphabetical by displayed label.
    public static var alphabetical: [ProgressQuestion] {
        allCases.filter { $0 != .workoutHistory }.sorted {
            let order = $0.displayName.localizedStandardCompare($1.displayName)
            return order == .orderedSame ? $0.rawValue < $1.rawValue : order == .orderedAscending
        }
    }
}

public struct ProgressQuestionSelection: Equatable, Sendable {
    public static let persistenceKey = "progress.selectedQuestion.v1"
    public private(set) var selected: ProgressQuestion

    public init(selected: ProgressQuestion = .strengthOverTime) {
        self.selected = selected == .workoutHistory ? .strengthOverTime : selected
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
        selected = question == .workoutHistory ? .strengthOverTime : question
    }
}
