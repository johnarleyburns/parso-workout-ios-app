import Foundation

/// Wall-clock workout timer (field-testing §02). Elapsed time is computed from
/// dates, never by counting ticks, so it stays correct after the app is
/// backgrounded (a phone call, the phone in a pocket). The UI's 1 Hz timer is
/// only a display refresh; this is the source of truth.
///
/// Pure value type with an injectable `now` so it's headlessly testable.
public struct WorkoutClock: Equatable, Sendable {
    public var startedAt: Date
    public var endedAt: Date?
    /// Total time spent paused before the current pause, excluded from elapsed.
    public var pausedAccumulated: TimeInterval
    /// When the current pause began, or nil if running.
    public var pausedSince: Date?

    public init(startedAt: Date = Date(),
                endedAt: Date? = nil,
                pausedAccumulated: TimeInterval = 0,
                pausedSince: Date? = nil) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.pausedAccumulated = pausedAccumulated
        self.pausedSince = pausedSince
    }

    public var isPaused: Bool { pausedSince != nil }
    public var isEnded: Bool { endedAt != nil }

    /// Active elapsed seconds (excludes paused spans), correct across
    /// backgrounding because it derives from wall-clock dates.
    public func elapsed(now: Date = Date()) -> TimeInterval {
        let reference = endedAt ?? now
        let gross = max(0, reference.timeIntervalSince(startedAt))
        let currentPause = pausedSince.map { max(0, reference.timeIntervalSince($0)) } ?? 0
        return max(0, gross - pausedAccumulated - currentPause)
    }

    // MARK: Mutations

    public mutating func pause(now: Date = Date()) {
        guard !isEnded, pausedSince == nil else { return }
        pausedSince = now
    }

    public mutating func resume(now: Date = Date()) {
        guard let since = pausedSince else { return }
        pausedAccumulated += max(0, now.timeIntervalSince(since))
        pausedSince = nil
    }

    public mutating func end(now: Date = Date()) {
        guard endedAt == nil else { return }
        // Fold any in-progress pause into the accumulator before stopping.
        if let since = pausedSince {
            pausedAccumulated += max(0, now.timeIntervalSince(since))
            pausedSince = nil
        }
        endedAt = now
    }
}
