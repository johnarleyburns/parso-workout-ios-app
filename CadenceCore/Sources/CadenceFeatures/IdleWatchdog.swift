import Foundation

/// Idle watchdog for a live strength session (launch-blockers plan, Phase 1a).
///
/// A workout must NEVER be ended by the system — only an explicit user tap ends
/// it (decisions.md #1, 2026-07-18). This type makes auto-end *unrepresentable*:
/// `TickResult` has no end case, so ignoring the prompt can only auto-**pause**
/// the workout. The clock stops, the workout is preserved.
///
/// Pure value type driven by injected dates so it is headlessly testable.
public struct IdleWatchdog: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// Counting quiet time since the last recorded activity.
        case idle(lastActivity: Date)
        /// The "Still training?" prompt is up; ignoring it auto-pauses.
        case prompting(since: Date)
        /// The prompt went unanswered and the workout was auto-paused.
        case autoPaused
    }

    /// What the caller should do after a tick. There is deliberately NO `.end`
    /// case — the system can never end a workout on its own.
    public enum TickResult: Equatable, Sendable {
        case none
        case showPrompt
        case autoPause
    }

    /// Seconds an unanswered prompt waits before the workout auto-pauses.
    public static let promptGraceSeconds: TimeInterval = 30

    public private(set) var state: State

    public init(now: Date = Date()) {
        state = .idle(lastActivity: now)
    }

    /// Any tap, keystroke, logged set, or foregrounding. Clears an active
    /// prompt or auto-pause and restarts the quiet-time counter.
    public mutating func recordActivity(now: Date = Date()) {
        state = .idle(lastActivity: now)
    }

    /// Advances the watchdog. `isPaused` freezes it (a paused workout never
    /// prompts); `enabled` is the user's opt-out.
    public mutating func tick(now: Date,
                              timeoutMinutes: Int,
                              isPaused: Bool,
                              enabled: Bool) -> TickResult {
        guard enabled, !isPaused else { return .none }
        switch state {
        case .idle(let lastActivity):
            let timeout = TimeInterval(max(1, timeoutMinutes) * 60)
            guard now.timeIntervalSince(lastActivity) >= timeout else { return .none }
            state = .prompting(since: now)
            return .showPrompt
        case .prompting(let since):
            guard now.timeIntervalSince(since) >= Self.promptGraceSeconds else { return .none }
            state = .autoPaused
            return .autoPause
        case .autoPaused:
            return .none
        }
    }
}
