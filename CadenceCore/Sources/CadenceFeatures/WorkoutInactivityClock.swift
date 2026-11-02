import Foundation

/// Time seam for the strength inactivity watchdog (phone coordinator, Watch watchdog,
/// completion/reconciliation). Production uses `SystemWorkoutInactivityClock`; tests inject a
/// manual clock that advances instantly, so no test ever waits ten real minutes.
public protocol WorkoutInactivityClock: Sendable {
    var now: Date { get }
    func sleep(until: Date) async throws
}

/// Real wall-clock implementation. Returns immediately when the target is already past.
public struct SystemWorkoutInactivityClock: WorkoutInactivityClock {
    public init() {}
    public var now: Date { Date() }
    public func sleep(until: Date) async throws {
        let interval = until.timeIntervalSince(Date())
        guard interval > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(min(interval, 86_400) * 1_000_000_000))
    }
}

public extension ActiveWorkoutModel {
    /// Clock-driven variant of `reconcileStrengthInactivity` (same policy, injected time).
    @discardableResult
    func reconcileStrengthInactivity(enabled: Bool, timeoutMinutes: Int,
                                     clock: any WorkoutInactivityClock) -> FinalizeResult? {
        reconcileStrengthInactivity(enabled: enabled, timeoutMinutes: timeoutMinutes, now: clock.now)
    }
}
