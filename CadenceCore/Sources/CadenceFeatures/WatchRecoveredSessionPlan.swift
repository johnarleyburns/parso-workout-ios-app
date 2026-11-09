import Foundation

/// Decides how a freshly launched Watch process treats a HealthKit workout
/// session handed back by `recoverActiveWorkoutSession`, and which identity
/// (`isActive` / `phoneRequestID`) it reconstructs from durable metadata.
public struct WatchRecoveredSessionPlan: Equatable, Sendable {
    public enum SessionState: Equatable, Sendable { case running, paused, stopped, ended, other }
    public enum Action: Equatable, Sendable {
        /// Genuinely finished: never resurrect; just clear saved metadata.
        case discardEnded
        /// Stopped but never ended: end it, then clear saved metadata.
        case endStopped
        /// Still live: re-adopt it.
        case adopt
    }

    public let action: Action
    public let isActive: Bool
    public let isMonitoring: Bool
    public let phoneRequestID: String?

    public init(state: SessionState, persistedMonitoring: Bool, persistedPhoneRequestID: String?) {
        switch state {
        case .ended: action = .discardEnded
        case .stopped: action = .endStopped
        default: action = .adopt
        }
        let adopting = action == .adopt
        isMonitoring = adopting && persistedMonitoring
        isActive = adopting && !persistedMonitoring
        // A monitoring session is never phone-owned.
        let id = persistedPhoneRequestID.flatMap { UUID(uuidString: $0) == nil ? nil : $0 }
        phoneRequestID = adopting && !persistedMonitoring ? id : nil
    }
}
