import Foundation

/// Public façade over the load-classification rules the coach and the UI both
/// need. Kept separate from `PrescriptionMath` (internal, rule-engine detail) so
/// the app can ask "should this render as BW?" without importing rule internals.
public enum ExerciseLoading {
    /// True when the movement is performed against bodyweight — catalog
    /// equipment wins, keyword fallback covers user-created movements.
    public static func isBodyweight(named name: String) -> Bool {
        PrescriptionMath.isBodyweightMovement(named: name)
    }

    /// True when the movement is programmed as a timed hold rather than reps.
    public static func isTimeHold(named name: String) -> Bool {
        PrescriptionMath.isTimeHold(named: name)
    }
}
