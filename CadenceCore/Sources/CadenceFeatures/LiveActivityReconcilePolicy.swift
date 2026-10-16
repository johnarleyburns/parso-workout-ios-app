import Foundation

/// Decides what to do with the workout Live Activity (which also mirrors to the
/// Watch Smart Stack) given the app's real workout state. An activity that
/// outlives its workout keeps an elapsed counter running on the lock screen and
/// Watch, so any non-active state must tear every owned activity down, even ones
/// this process never adopted (orphaned by a kill, background finish, or relaunch).
public enum LiveActivityReconcilePolicy {
    public enum Action: Equatable, Sendable {
        case update
        case endAll
    }

    /// How long past its last update an activity may linger before the system
    /// greys it out. The app refreshes it on a heartbeat while active.
    public static let staleAfter: TimeInterval = 15 * 60

    public static func action(workoutIsActive: Bool, hasStrengthSession: Bool,
                              ownedActivityCount: Int) -> Action? {
        if workoutIsActive && hasStrengthSession { return .update }
        return ownedActivityCount > 0 ? .endAll : nil
    }

    public static func staleDate(from now: Date) -> Date {
        now.addingTimeInterval(staleAfter)
    }
}
