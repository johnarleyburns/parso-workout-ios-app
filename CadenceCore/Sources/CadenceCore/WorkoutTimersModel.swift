import Foundation

/// One always-on stopwatch for the strength session. It is either the current
/// **work** interval or the **rest** interval — never idle during a live
/// workout. Opening the set editor starts work; logging (or cancelling) starts
/// rest again. Workout pause suspends the running interval.
public struct WorkoutTimersModel: Equatable, Sendable {
    public enum Mode: String, Sendable, Equatable {
        case work
        case rest
    }

    public private(set) var mode: Mode
    /// Seconds banked before the current running span.
    public private(set) var accumulated: TimeInterval
    /// When the current running span started (nil while the workout is paused).
    public private(set) var startedAt: Date?

    public init(mode: Mode = .rest,
                accumulated: TimeInterval = 0,
                startedAt: Date? = nil) {
        self.mode = mode
        self.accumulated = accumulated
        self.startedAt = startedAt
    }

    /// Total seconds in the current interval at `now`.
    public func elapsed(now: Date) -> TimeInterval {
        var total = accumulated
        if let startedAt {
            total += max(0, now.timeIntervalSince(startedAt))
        }
        return total
    }

    public var isRunning: Bool { startedAt != nil }

    /// Starts the initial rest interval on first appearance.
    public mutating func startRestIfNeeded(now: Date) {
        guard startedAt == nil, accumulated == 0 else { return }
        mode = .rest
        startedAt = now
    }

    /// Opening the Add Set editor starts the work interval from zero.
    public mutating func beginWork(now: Date) {
        guard mode != .work || startedAt == nil else { return }
        mode = .work
        accumulated = 0
        startedAt = now
    }

    /// Logging a set (or leaving its editor) starts the rest interval from zero.
    public mutating func beginRest(now: Date) {
        guard mode != .rest || startedAt == nil else { return }
        mode = .rest
        accumulated = 0
        startedAt = now
    }

    public mutating func pause(now: Date) {
        guard let startedAt else { return }
        accumulated += max(0, now.timeIntervalSince(startedAt))
        self.startedAt = nil
    }

    public mutating func resume(now: Date) {
        guard startedAt == nil else { return }
        startedAt = now
    }

    /// Freezes the timer when the workout ends.
    public mutating func stop(now: Date) {
        pause(now: now)
    }
}
