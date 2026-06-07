import Foundation

/// Watches for an abandoned workout (field-testing §02, decisions #6/#7). After
/// `timeout` seconds with no activity the workout should prompt "Still
/// training?" and, on no response, auto-save (handled by the app layer). The
/// watchdog is *disarmed* while an interval/round timer is actively running so a
/// long work block isn't mistaken for idleness.
///
/// Pure value type with an injectable `now` for headless testing.
public struct IdleWatchdog: Equatable, Sendable {
    /// Idle timeout in seconds. Default 10 minutes (decision #7), adjustable.
    public var timeout: TimeInterval
    /// Timestamp of the last user/sensor activity.
    public var lastActivityAt: Date
    /// When false, the watchdog never expires (e.g. an interval round is live).
    public var isArmed: Bool

    public init(timeout: TimeInterval = 600,
                lastActivityAt: Date = Date(),
                isArmed: Bool = true) {
        self.timeout = timeout
        self.lastActivityAt = lastActivityAt
        self.isArmed = isArmed
    }

    /// Records activity (a logged set, a movement/HR sample, a tap), resetting
    /// the countdown.
    public mutating func poke(now: Date = Date()) {
        lastActivityAt = now
    }

    /// Seconds remaining until expiry, or nil when disarmed.
    public func remaining(now: Date = Date()) -> TimeInterval? {
        guard isArmed else { return nil }
        return max(0, timeout - now.timeIntervalSince(lastActivityAt))
    }

    /// True once the idle period has elapsed (and the watchdog is armed).
    public func hasExpired(now: Date = Date()) -> Bool {
        guard isArmed else { return false }
        return now.timeIntervalSince(lastActivityAt) >= timeout
    }
}
