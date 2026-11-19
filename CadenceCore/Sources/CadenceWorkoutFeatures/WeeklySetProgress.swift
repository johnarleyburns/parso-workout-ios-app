import CadenceFeatures
import Foundation

/// A shared, evidence-backed weekly set scale for Home's muscle-group and
/// individual-muscle rows. SwiftUI maps these semantic roles to actual colors.
public enum WeeklySetTintRole: Sendable, Equatable {
    case red
    case yellow
    case lightGreen
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
        case .belowMinimum: {
            #if os(Linux)
            "Below 4-set minimum"
            #else
            String(localized: "Below 4-set minimum", bundle: FeatureLocalization.bundle)
            #endif
        }()
        case .building: {
            #if os(Linux)
            "Building toward productive volume"
            #else
            String(localized: "Building toward productive volume", bundle: FeatureLocalization.bundle)
            #endif
        }()
        case .productive: {
            #if os(Linux)
            "Productive 8–12-set range"
            #else
            String(localized: "Productive 8–12-set range", bundle: FeatureLocalization.bundle)
            #endif
        }()
        case .aboveMaximum: {
            #if os(Linux)
            "Above 12-set maximum"
            #else
            String(localized: "Above 12-set maximum", bundle: FeatureLocalization.bundle)
            #endif
        }()
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

/// Weekly cardio scale on the same red/yellow/green roles as weekly sets:
/// 150 moderate-equivalent minutes is the guideline minimum, 300 the goal.
public enum WeeklyCardioProgress {
    public static let minimum = 150.0
    public static let target = 300.0

    public static func tintRole(for moderateEquivalentMinutes: Double) -> WeeklySetTintRole {
        WeeklyActivityColor.cardio(moderateEquivalentMinutes)
    }
}

/// Absolute weekly activity bands, independent of a user's ring-fill target.
public enum WeeklyActivityColor {
    public static func strength(_ sets: Double) -> WeeklySetTintRole {
        band(sets, minimum: 128, upper: 192)
    }

    public static func cardio(_ minutes: Double) -> WeeklySetTintRole {
        band(minutes, minimum: 150, upper: 300)
    }

    private static func band(_ value: Double, minimum: Double, upper: Double) -> WeeklySetTintRole {
        guard value.isFinite, value > 0 else { return .red }
        if value < minimum { return .yellow }
        if value < upper { return .lightGreen }
        return .green
    }
}
