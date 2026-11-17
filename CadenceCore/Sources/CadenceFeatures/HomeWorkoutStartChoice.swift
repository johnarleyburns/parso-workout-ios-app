import Foundation
import CadenceCore

public enum HomeStrengthStartChoice: String, CaseIterable, Identifiable, Sendable {
    case quickStart, suggested, previous
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .quickStart: "Quick Start"
        case .suggested: "Suggested"
        case .previous: "Previous"
        }
    }
}

public enum HomeRecentCardioChoices {
    public static func recent<T: Hashable>(_ types: [T]) -> [T] {
        var seen = Set<T>()
        return Array(types.filter { seen.insert($0).inserted }.prefix(3))
    }
}


/// Shared ordering and destinations for the phone popup and Watch wheel.
/// Titles are localized by the presenting app's string catalog.
public enum HomeWorkoutStartChoice: Hashable, Identifiable, Sendable {
    case strength(HomeStrengthStartChoice)
    case cardio(WorkoutType)

    public static let selectionStorageKey = "home.workoutStartChoice"
    public static let defaultChoice: Self = .strength(.suggested)

    /// Persist stable identities rather than localized labels or list positions.
    /// Unknown values fall back safely if a future release removes a choice.
    public static func restored(from identifier: String) -> Self {
        allChoices.first { $0.id == identifier } ?? defaultChoice
    }

    public static let strengthChoices: [Self] = [.strength(.suggested), .strength(.previous), .strength(.quickStart)]
    public static let cardioChoices: [Self] = ([WorkoutType.hiit] + WorkoutType.allCases.filter {
        $0 != .weights && $0 != .hiit
    }).map { .cardio($0) }
    public static let allChoices = strengthChoices + cardioChoices

    public var id: String {
        switch self {
        case .strength(let source): "strength.\(source.rawValue)"
        case .cardio(let type): "cardio.\(type.rawValue)"
        }
    }

    public var title: String {
        switch self {
        case .strength(.suggested): "Optimal Lifts"
        case .strength(.previous): "Repeat Lifts"
        case .strength(.quickStart): "Quick Start"
        case .cardio(.other): "Custom Cardio"
        case .cardio(let type): type.displayName
        }
    }

    public var symbol: String {
        switch self {
        case .strength(.suggested): "dumbbell.fill"
        case .strength(.previous): "dumbbell.fill"
        case .strength(.quickStart): "dumbbell.fill"
        case .cardio(let type): type.symbol
        }
    }
}
