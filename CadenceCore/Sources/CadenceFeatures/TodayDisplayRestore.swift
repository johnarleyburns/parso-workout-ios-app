import Foundation

/// Phase of Today's first-frame durable display restore. Expensive Today work
/// (history-derived identity, HealthKit waits, full-coach hydration) must not
/// begin until this reaches `.finished`.
public enum TodayDisplayRestoreState: Equatable, Sendable {
    case notStarted, restoring, finished

    /// Whether history-derived work may start. Only the Today surface owns the
    /// durable files; This Week never waits for them.
    public func permitsHydration(isToday: Bool) -> Bool {
        !isToday || self == .finished
    }
}

/// Identity of the restore task: local day and surface only. It deliberately
/// carries no query, settings, or HealthKit values.
public struct TodayDisplayRestoreID: Equatable, Sendable {
    public let dayKey: String
    public let isToday: Bool
    public init(dayKey: String, isToday: Bool) {
        self.dayKey = dayKey
        self.isToday = isToday
    }
}
