import Foundation

/// Pure lifecycle reducer for the iPhone-side HealthKit mirrored workout session.
/// Generations identify successive mirrored-session instances so a stale
/// disconnect/end from a superseded session can never clear a newer one.
public struct WorkoutMirrorLifecycle: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case inactive
        case starting
        case mirrored(generation: Int)
        /// Recoverable, not terminal: HealthKit supplies a replacement
        /// mirrored session on reconnect, so this carries the generation
        /// that disconnected so a later `.ended`/`.failed` for that same
        /// generation can still resolve it (see `apply`), and a stale one
        /// cannot.
        case disconnected(generation: Int)
    }

    public enum Event: Equatable, Sendable {
        case startRequested
        /// HealthKit supplied a (new or replacement) mirrored session.
        case attached
        case disconnected(generation: Int)
        case ended(generation: Int)
        case failed(generation: Int)
    }

    public private(set) var state: State = .inactive
    /// Monotonic count of attached sessions; the newest attach owns this value.
    public private(set) var latestGeneration = 0

    public init() {}

    @discardableResult
    public mutating func apply(_ event: Event) -> State {
        switch event {
        case .startRequested:
            if case .mirrored = state { break }
            state = .starting
        case .attached:
            latestGeneration &+= 1
            state = .mirrored(generation: latestGeneration)
        case .disconnected(let g):
            if case .mirrored(let current) = state, current == g {
                state = .disconnected(generation: g)
            }
        case .failed(let g):
            if case .mirrored(let current) = state, current == g {
                state = .disconnected(generation: g)
            } else if case .disconnected(let current) = state, current == g {
                // A genuine failure for the session that's already
                // disconnected is terminal: don't strand it in
                // .disconnected forever.
                state = .inactive
            }
        case .ended(let g):
            if case .mirrored(let current) = state, current == g {
                state = .inactive
            } else if case .disconnected(let current) = state, current == g {
                // Same rationale as .failed above: a genuine end arriving
                // after a disconnect must still resolve to .inactive.
                state = .inactive
            }
        }
        return state
    }

    /// True only while actively mirroring data for exactly this generation.
    /// False in every other state (`.inactive`, `.starting`,
    /// `.disconnected`) and false for any generation other than the current
    /// one — including a stale/superseded generation — so callers can guard
    /// `didReceiveDataFromRemoteWorkoutSession` against forwarding data from
    /// a session that has since been replaced.
    public func shouldForwardData(generation: Int) -> Bool {
        state == .mirrored(generation: generation)
    }

    /// Mirror setup is best-effort: the Watch primary workout always starts.
    public static func shouldStartPrimary(mirrorSucceeded: Bool) -> Bool { true }
}
