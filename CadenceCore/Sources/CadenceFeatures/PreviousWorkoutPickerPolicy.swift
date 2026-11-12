import Foundation
import CadenceCore

/// Which past sessions a "start/reuse from a previous workout" picker offers:
/// the 20 most recent sessions that have logged sets, excluding the current one.
public enum PreviousWorkoutPickerPolicy {
    public static let limit = 20

    public static func candidates(sessions: [WorkoutSession], excluding: WorkoutSession) -> [WorkoutSession] {
        let excludedID = excluding.id
        let eligible = sessions.lazy.filter { $0.id != excludedID && $0.hasSets }
        // Callers' @Query is already newest-first; sorting (stable) keeps the
        // cap correct for any input order.
        return Array(eligible.sorted { $0.date > $1.date }.prefix(limit))
    }
}
