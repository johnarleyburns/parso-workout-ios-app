import Foundation

/// Pure functions — no I/O, fully unit-testable. Used by trends/PRs later.
public enum WorkoutMath {

    /// Epley estimated one-rep max. Returns the weight unchanged at 1 rep,
    /// and 0 for non-positive reps.
    public static func epley1RM(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return 0 }
        if reps == 1 { return weight }
        return weight * (1.0 + Double(reps) / 30.0)
    }

    /// Volume for a single set = weight × reps.
    public static func volume(weight: Double, reps: Int) -> Double {
        weight * Double(max(0, reps))
    }
}
