import Foundation
import SwiftData
import CadenceCore

/// Deleting a stale watch-only workout without entering it.
///
/// The watch's Resume row used to be reachable only by *tapping* it, which opens
/// the workout and starts an `HKWorkoutSession` — a heavy, side-effectful way to
/// get rid of a session the user has already abandoned. This mirrors
/// `WatchStrengthFlowModel.cancel()` so both routes delete identically and tell
/// the phone the same thing.
public enum WatchResumableSession {

    /// Deletes `session` locally and returns the payload the phone needs to drop
    /// its copy, or `nil` when the session never had a set worth syncing (the
    /// phone has nothing to forget in that case).
    @discardableResult
    public static func discard(_ session: WorkoutSession, in context: ModelContext) -> [String: String]? {
        let hadSets = !(session.sets ?? []).isEmpty
        let id = session.id.uuidString
        context.delete(session)
        try? context.save()
        return hadSets ? ["action": "discard_session", "session_id": id] : nil
    }
}
