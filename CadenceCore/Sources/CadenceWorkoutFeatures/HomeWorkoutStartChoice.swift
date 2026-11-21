import CadenceFeatures
import Foundation
import CadenceCore

/// The single strength launch offered on iPhone and Apple Watch. Field testing
/// removed the separate Repeat and Custom rows: Lift is the personalized
/// strength workout, reviewed on a read-first plan screen before starting.
public enum HomeStrengthStartChoice: String, CaseIterable, Identifiable, Sendable {
    case suggested
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .suggested: "Lift"
        }
    }
}

public enum HomeRecentCardioChoices {
    public static func recent<T: Hashable>(_ types: [T]) -> [T] {
        var seen = Set<T>()
        return Array(types.filter { seen.insert($0).inserted }.prefix(3))
    }
}


/// Shared ordering and destinations for the phone list and Watch launcher.
/// Titles are localized by the presenting app's string catalog.
public enum HomeWorkoutStartChoice: Hashable, Identifiable, Sendable {
    case strength(HomeStrengthStartChoice)
    case cardio(WorkoutType)
    /// Cardio's counterpart to `.strength(.suggested)`: suggests a cardio
    /// session the same way strength suggestions already work, rather than
    /// picking a fixed `WorkoutType`.
    case suggestedCardio

    public static let selectionStorageKey = "home.workoutStartChoice"
    public static let defaultChoice: Self = .strength(.suggested)

    /// Persist stable identities rather than localized labels or list positions.
    /// Unknown values fall back safely if a future release removes a choice.
    public static func restored(from identifier: String) -> Self {
        allChoices.first { $0.id == identifier } ?? defaultChoice
    }

    /// Only the personalized Lift starts strength. The retired Repeat/Custom
    /// identifiers are intentionally absent so an older saved selection falls
    /// back to Lift instead of resurrecting a removed row.
    public static let strengthChoices: [Self] = [.strength(.suggested)]
    /// Fixed cardio types first, then the coach's recommendation last. Putting
    /// Recommend at the bottom keeps the concrete choices predictable while
    /// still offering the personalized option.
    public static let cardioChoices: [Self] = {
        let fixedTypes = [WorkoutType.hiit] + WorkoutType.allCases.filter {
            $0 != .weights && $0 != .hiit
        }
        return fixedTypes.map { HomeWorkoutStartChoice.cardio($0) }
            + [HomeWorkoutStartChoice.suggestedCardio]
    }()
    public static let allChoices = strengthChoices + cardioChoices

    public var id: String {
        switch self {
        case .strength(let source): "strength.\(source.rawValue)"
        case .cardio(let type): "cardio.\(type.rawValue)"
        case .suggestedCardio: "cardio.suggested"
        }
    }

    public var title: String {
        switch self {
        case .strength(.suggested): "Lift"
        case .cardio(.other): "Other"
        case .cardio(let type): type.displayName
        case .suggestedCardio: "Recommend"
        }
    }

    public var symbol: String {
        switch self {
        case .strength(.suggested): "dumbbell.fill"
        case .cardio(let type): type.symbol
        case .suggestedCardio: "wand.and.stars"
        }
    }
}
