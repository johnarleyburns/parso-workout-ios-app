import Foundation

/// A wall-clock countdown for a fixed-length guided phase (warm-up / cool-down).
///
/// Like `WorkoutClock`, remaining/elapsed time is derived from dates — never by
/// counting ticks — so the countdown **keeps running while the app is
/// backgrounded** and is correct the instant the user returns. It only stops
/// advancing when explicitly paused. The view's 1 Hz timer is a display refresh
/// only; this value type is the source of truth.
///
/// Pure and `Sendable` with an injectable `now`, so it's headlessly testable.
public struct PhaseCountdownClock: Equatable, Sendable {
    /// Configured length of the phase, in seconds.
    public let total: TimeInterval
    public var startedAt: Date
    public var pausedAccumulated: TimeInterval
    public var pausedSince: Date?

    public init(total: TimeInterval, startedAt: Date = Date()) {
        self.total = max(0, total)
        self.startedAt = startedAt
        self.pausedAccumulated = 0
        self.pausedSince = nil
    }

    public var isPaused: Bool { pausedSince != nil }

    /// Real time consumed since start, excluding paused spans. Survives
    /// backgrounding because it is computed from wall-clock dates.
    public func elapsed(now: Date = Date()) -> TimeInterval {
        let gross = max(0, now.timeIntervalSince(startedAt))
        let currentPause = pausedSince.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return max(0, gross - pausedAccumulated - currentPause)
    }

    /// Seconds remaining, clamped to `[0, total]`.
    public func remaining(now: Date = Date()) -> TimeInterval {
        max(0, total - elapsed(now: now))
    }

    public func isFinished(now: Date = Date()) -> Bool {
        remaining(now: now) <= 0
    }

    /// Seconds actually consumed so far, clamped to `total` — what history records
    /// (e.g. skipping a 10:00 cool-down at 3:00 reports 180).
    public func consumed(now: Date = Date()) -> TimeInterval {
        min(total, elapsed(now: now))
    }

    /// Pause the countdown. Idempotent — a second pause is a no-op.
    public mutating func pause(now: Date = Date()) {
        guard pausedSince == nil else { return }
        pausedSince = now
    }

    /// Resume a paused countdown, folding the paused span into the accumulator.
    /// Idempotent when already running.
    public mutating func resume(now: Date = Date()) {
        guard let since = pausedSince else { return }
        pausedAccumulated += max(0, now.timeIntervalSince(since))
        pausedSince = nil
    }
}
