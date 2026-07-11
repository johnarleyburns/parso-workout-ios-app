import Foundation

/// Tracks the strength session's **work** vs **rest** stopwatch (issue 9). Exactly
/// one mode runs at a time; switching modes banks the elapsed span into the
/// previous mode's accumulator and restarts the clock. Pure/derived so it's
/// `swift test`-verifiable — the view drives it with a 1 Hz redraw tick and reads
/// `elapsed(mode:now:)` for the live value.
public struct WorkoutTimersModel: Equatable, Sendable {
    public enum Mode: String, Sendable, Equatable {
        case idle
        case work
        case rest
    }

    public private(set) var mode: Mode
    /// Banked elapsed time (seconds) per mode, excluding the currently-running span.
    public private(set) var accumulated: [Mode: TimeInterval]
    /// When the current running span started (nil when idle).
    public private(set) var startedAt: Date?

    public init(mode: Mode = .idle,
                accumulated: [Mode: TimeInterval] = [:],
                startedAt: Date? = nil) {
        self.mode = mode
        self.accumulated = accumulated
        self.startedAt = startedAt
    }

    /// Total elapsed seconds for `mode` at `now`, including any currently-running span.
    public func elapsed(_ query: Mode, now: Date) -> TimeInterval {
        var total = accumulated[query] ?? 0
        if query == mode, let start = startedAt {
            total += max(0, now.timeIntervalSince(start))
        }
        return total
    }

    /// Switches to `target`, banking the running span into the previous mode.
    /// Tapping the already-active mode stops it (returns to `.idle`).
    public mutating func toggle(_ target: Mode, now: Date) {
        bankRunningSpan(now: now)
        if mode == target {
            mode = .idle
            startedAt = nil
        } else {
            mode = target
            startedAt = target == .idle ? nil : now
        }
    }

    /// Stops any running span (e.g. on pause / workout end), banking it.
    public mutating func stop(now: Date) {
        bankRunningSpan(now: now)
        mode = .idle
        startedAt = nil
    }

    private mutating func bankRunningSpan(now: Date) {
        guard mode != .idle, let start = startedAt else { return }
        accumulated[mode, default: 0] += max(0, now.timeIntervalSince(start))
        startedAt = nil
    }
}
