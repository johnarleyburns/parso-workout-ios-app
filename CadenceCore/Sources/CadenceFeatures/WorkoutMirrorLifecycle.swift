import Foundation

/// Pure lifecycle reducer for the iPhone-side HealthKit mirrored workout session.
/// Generations identify successive mirrored-session instances so a stale
/// disconnect/end from a superseded session can never clear a newer one.
public struct WorkoutMirrorLifecycle: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case inactive
        case starting
        case mirrored(generation: Int)
        case disconnected
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
        case .disconnected(let g), .failed(let g):
            if case .mirrored(let current) = state, current == g { state = .disconnected }
        case .ended(let g):
            if case .mirrored(let current) = state, current == g { state = .inactive }
        }
        return state
    }

    /// Mirror setup is best-effort: the Watch primary workout always starts.
    public static func shouldStartPrimary(mirrorSucceeded: Bool) -> Bool { true }
}
