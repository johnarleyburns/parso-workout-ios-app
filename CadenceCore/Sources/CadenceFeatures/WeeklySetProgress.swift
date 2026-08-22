import Foundation

/// A shared, evidence-backed weekly set scale for Home's muscle-group and
/// individual-muscle rows. SwiftUI maps these semantic roles to actual colors.
public enum WeeklySetTintRole: Sendable, Equatable {
    case red
    case yellow
    case green
}

public enum WeeklySetZone: Sendable, Equatable {
    case belowMinimum
    case building
    case productive
    case aboveMaximum

    public var tintRole: WeeklySetTintRole {
        switch self {
        case .belowMinimum, .aboveMaximum: .red
        case .building: .yellow
        case .productive: .green
        }
    }

    public var displayText: String {
        switch self {
        case .belowMinimum: "Below 4-set minimum"
        case .building: "Building toward productive volume"
        case .productive: "Productive 8–12-set range"
        case .aboveMaximum: "Above 12-set maximum"
        }
    }

    public var accessibilityText: String { displayText }
}

public enum WeeklySetProgress {
    public static let minimum = 4.0
    public static let productive = 8.0
    public static let maximum = 12.0

    public static func zone(for sets: Double) -> WeeklySetZone {
        switch sets {
        case ..<minimum: .belowMinimum
        case ..<productive: .building
        case ...maximum: .productive
        default: .aboveMaximum
        }
    }

    public static func normalized(_ sets: Double) -> Double {
        min(max(sets, 0) / maximum, 1)
    }

    public static func formattedSets(_ sets: Double) -> String {
        sets.formatted(.number.precision(.fractionLength(sets.rounded() == sets ? 0 : 1)))
    }
}
