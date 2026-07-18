import Foundation
import CadenceCore

/// Finds the workout to re-adopt after a crash, force-quit, jetsam, or app
/// upgrade (launch-blockers plan, Phase 1e). A workout is NEVER lost: a
/// candidate of any age is adopted **paused** and surfaced via the Home
/// "Resume Workout" card — never auto-presented, never discarded.
public enum ActiveSessionRecovery {

    /// The most recent in-progress session: not ended, not deleted, and not a
    /// manual after-the-fact log.
    public static func candidate(in sessions: [WorkoutSession]) -> WorkoutSession? {
        sessions
            .filter { $0.endedAt == nil && $0.deletedAt == nil && !$0.isLogged }
            .max { $0.date < $1.date }
    }

    /// Elapsed seconds to credit on adoption: the heartbeat's elapsed when it
    /// matches the session, else 0 (unknown — credit nothing rather than count
    /// the dead gap as training time).
    public static func adoptedElapsed(sessionID: UUID, heartbeat: WorkoutHeartbeat?) -> TimeInterval {
        guard let heartbeat, heartbeat.sessionID == sessionID else { return 0 }
        return max(0, heartbeat.elapsed)
    }
}
