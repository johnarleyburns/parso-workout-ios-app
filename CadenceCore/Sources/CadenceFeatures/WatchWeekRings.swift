import Foundation
import CadenceCore

/// Semantic ring colour for the Watch This Week page; the view maps it to a `Color`.
public enum WatchWeekRingTone: Sendable, Equatable {
    /// Nothing logged yet.
    case red
    /// Some progress, below the minimum.
    case yellow
    /// Between the minimum and the upper limit.
    case lightBlue
    /// At or beyond the upper limit.
    case green
}

/// One of the two This Week rings (Strength sets, Cardio minutes) with its label text parts.
public struct WatchWeekRing: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case strength, cardio }
    public let kind: Kind
    public let value: Double
    public let minimum: Double
    public let target: Double
    public var id: Kind { kind }

    public init(kind: Kind, value: Double, minimum: Double, target: Double) {
        self.kind = kind
        self.value = max(0, value)
        self.minimum = max(0, minimum)
        self.target = max(0, target)
    }

    /// Ring fill, 0…1 of the upper limit.
    public var progress: Double { target > 0 ? min(1, value / target) : 0 }

    public var tone: WatchWeekRingTone {
        if value <= 0 { return .red }
        if value < minimum { return .yellow }
        if target > 0 && value < target { return .lightBlue }
        return .green
    }

    /// Whole number for display ("12"); fractional fractional-set credit is rounded.
    public var displayValue: Int { Int(value.rounded()) }
}

public enum WatchWeekRings {
    /// Strength first, then cardio. Cardio uses the 150/300 guideline scale shared with the phone;
    /// strength thresholds come from the phone because they scale with the muscle groups tracked.
    public static func rings(from summary: WatchSync.WeekSummary?) -> [WatchWeekRing] {
        let summary = summary ?? WatchSync.WeekSummary(
            sets: 0, setsMinimum: 0, setsTarget: 0, cardioMinutes: 0, updatedAt: .distantPast)
        let minimum = summary.setsMinimum > 0 ? summary.setsMinimum : WeeklySetProgress.minimum
        let target = summary.setsTarget > 0 ? summary.setsTarget : WeeklySetProgress.maximum
        return [
            WatchWeekRing(kind: .strength, value: summary.sets, minimum: minimum, target: target),
            WatchWeekRing(kind: .cardio, value: summary.cardioMinutes,
                          minimum: WeeklyCardioProgress.minimum, target: WeeklyCardioProgress.target),
        ]
    }
}
