import Foundation

/// Presentation-only state for the Watch Add Exercise confirmation. Tapping a
/// row (or Details → Add) only sets `pending`; the workout is mutated solely
/// through `confirm`, so Cancel and Retry can never change it on their own.
public struct WatchAddConfirmation: Equatable, Sendable {
    public struct Target: Equatable, Sendable {
        public let id: UUID
        public let name: String
        public init(id: UUID, name: String) {
            self.id = id
            self.name = name
        }
    }

    public enum Outcome: Equatable, Sendable {
        case alreadyPresent(name: String)
        case unavailable(Target)
        case saveFailed(Target)

        public var message: String {
            switch self {
            case .alreadyPresent: return "Already in this workout"
            case .unavailable(let t): return "\(t.name) is no longer available. Refresh and try again."
            case .saveFailed(let t): return "Couldn't save \(t.name). Try again."
            }
        }
    }

    public private(set) var pending: Target?
    public private(set) var outcome: Outcome?

    public init() {}

    public mutating func request(_ target: Target) {
        outcome = nil
        pending = target
    }

    public mutating func cancel() {
        pending = nil
    }

    /// Runs `add` exactly once for the pending target and records the outcome.
    /// Returns nil when nothing was pending.
    @discardableResult
    public mutating func confirm(
        add: (_ id: UUID, _ name: String) -> WatchExerciseAddResult
    ) -> WatchExerciseAddResult? {
        guard let target = pending else { return nil }
        pending = nil
        let result = add(target.id, target.name)
        switch result {
        case .added: outcome = nil
        case .alreadyPresent(let name): outcome = .alreadyPresent(name: name)
        case .unavailable: outcome = .unavailable(target)
        case .saveFailed: outcome = .saveFailed(target)
        }
        return result
    }

    /// Reopens the confirmation for a failed save; never mutates by itself.
    public mutating func retry() {
        guard case .saveFailed(let target)? = outcome else { return }
        outcome = nil
        pending = target
    }

    public mutating func dismissOutcome() {
        outcome = nil
    }
}
