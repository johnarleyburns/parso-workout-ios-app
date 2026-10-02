import Foundation

/// The This Week dashboard keeps disclosure state for each report independently.
/// This is UI state only; it never changes or filters workout data.
public enum WeeklyDetailMode: String, CaseIterable, Sendable, Identifiable {
    case muscleMap
    case muscleGroupVolume
    case strength
    case cardio

    public var id: String { rawValue }
}

public struct WeeklyDetailSelection: Equatable, Sendable {
    public static let persistenceKey = "home.thisWeek.weeklyDetailSelection.v2"
    public private(set) var expanded: Set<WeeklyDetailMode>

    public init(expanded: Set<WeeklyDetailMode> = [.muscleMap]) {
        self.expanded = expanded
    }

    public static func persisted(defaults: UserDefaults = .standard) -> Self {
        guard let rawValues = defaults.stringArray(forKey: persistenceKey) else {
            return Self()
        }
        let values = Set(rawValues.compactMap(WeeklyDetailMode.init(rawValue:)))
        return Self(expanded: values)
    }

    public func persist(defaults: UserDefaults = .standard) {
        defaults.set(expanded.map(\.rawValue).sorted(), forKey: Self.persistenceKey)
    }

    public mutating func toggle(_ mode: WeeklyDetailMode) {
        if expanded.contains(mode) {
            expanded.remove(mode)
        } else {
            expanded.insert(mode)
        }
    }

    public mutating func select(_ mode: WeeklyDetailMode) {
        expanded.insert(mode)
    }

    public func isExpanded(_ mode: WeeklyDetailMode) -> Bool {
        expanded.contains(mode)
    }
}

/// Where a Today → This Week tap should land. The weekly rings map sets to
/// muscle coverage, sessions to Strength, and cardio minutes to Cardio.
public enum ThisWeekDestination: String, CaseIterable, Sendable {
    case muscleCoverage
    case strength
    case cardio

    public static func forRing(_ kind: WeekRing.Kind) -> ThisWeekDestination {
        switch kind {
        case .sets: return .muscleCoverage
        case .sessions: return .strength
        case .cardioMinutes: return .cardio
        }
    }

    public var detailMode: WeeklyDetailMode {
        switch self {
        case .muscleCoverage: return .muscleMap
        case .strength: return .strength
        case .cardio: return .cardio
        }
    }
}
