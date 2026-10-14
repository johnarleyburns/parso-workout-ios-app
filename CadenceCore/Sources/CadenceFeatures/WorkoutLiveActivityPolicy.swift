import Foundation

/// Pure lifecycle rules for the workout Live Activity (mirrored to the Watch
/// Smart Stack). Kept out of ActivityKit code so the "never leave a counter
/// running after the workout ended" guarantee is unit-tested headlessly
/// (field report: issue #74).
public enum WorkoutLiveActivityPolicy {
    /// The app refreshes the activity on a heartbeat while a workout is active.
    /// If the app stops refreshing (killed, crashed, workout finished elsewhere)
    /// the system marks the activity stale after this long.
    public static let staleAfter: TimeInterval = 10 * 60

    public enum Reconciliation: Equatable, Sendable {
        /// Keep/start an activity for the running workout.
        case runActivity
        /// End every activity this app owns, including ones orphaned by a previous launch.
        case endAllActivities
    }

    public static func reconciliation(workoutIsActive: Bool) -> Reconciliation {
        workoutIsActive ? .runActivity : .endAllActivities
    }

    public static func staleDate(from now: Date) -> Date {
        now.addingTimeInterval(staleAfter)
    }
}
