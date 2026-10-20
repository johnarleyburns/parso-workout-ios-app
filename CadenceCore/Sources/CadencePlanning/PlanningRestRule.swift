import Foundation

/// A rest-day rule expressed with plain integers so the domain needs no app types.
/// Weekdays use the Gregorian numbering (Sunday = 1 … Saturday = 7).
public enum PlanningRestRule: Sendable, Equatable {
    case fixed(weekdays: Set<Int>)
    case rolling(everyNDays: Int)

    /// Whether a day is a rest day. `daysSinceWeekStart` is only consulted by
    /// `.rolling`; the caller (an adapter) owns calendar arithmetic.
    public static func isRestDay(weekday: Int, daysSinceWeekStart: Int, rule: PlanningRestRule) -> Bool {
        switch rule {
        case .fixed(let weekdays):
            return weekdays.contains(weekday)
        case .rolling(let everyNDays):
            let cycleLength = everyNDays + 1
            return daysSinceWeekStart > 0 && (daysSinceWeekStart % cycleLength) == everyNDays
        }
    }
}
