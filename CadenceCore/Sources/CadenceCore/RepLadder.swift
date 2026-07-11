import Foundation

/// Generates **descending rep ladders** for a prescribed strength session. The
/// evidence base is the load/rep continuum (Schoenfeld et al. 2021): heavier
/// low-rep work develops maximal strength, a moderate range near failure drives
/// hypertrophy, and higher reps at lighter loads bias local endurance.
///
/// Rather than flattening every set to the low bound of the rep range (the old
/// behaviour — a hypertrophy user got `6,6,6`), the coach prescribes a productive
/// descending pyramid across the range, e.g. hypertrophy 3 sets → `12,10,8`,
/// strength 3 sets → `5,5,3`, endurance 3 sets → `20,18,16`.
///
/// Pure and `swift test`-verifiable; both prescription paths (single-lift recs and
/// coach-built sessions) thread through here so the phone logger seeds each set
/// from the ladder index-wise.
public enum RepLadder {

    /// A descending rep ladder for `goal` across `sets` working sets, spanning the
    /// goal's `repRange`.
    public static func ladder(for goal: TrainingGoal, sets: Int) -> [Int] {
        ladder(low: goal.repRange.lowerBound, high: goal.repRange.upperBound, sets: sets)
    }

    /// A descending rep ladder across the explicit `low…high` rep range for `sets`
    /// working sets. Strategy is chosen by range width so it works for any goal's
    /// prescribed range:
    ///
    /// - Wide ranges (hypertrophy 6…12, endurance 15…20): descend by 2 from the top,
    ///   clamped at `low` — `12,10,8,6…` / `20,18,16,15…`.
    /// - Narrow ranges (strength 3…5, width ≤ 2): a heavy top-set **hold** — the
    ///   first half of the sets at `high`, the rest at `low` (`5,5,3` / `5,5,3,3`),
    ///   matching how lifters ramp heavy triples/fives.
    ///
    /// `sets <= 0` returns an empty ladder; a single set returns the productive
    /// midpoint of the range (not the floor). Every value is clamped to `low…high`.
    public static func ladder(low: Int, high: Int, sets: Int) -> [Int] {
        guard sets > 0 else { return [] }
        let lo = min(low, high)
        let hi = max(low, high)

        // A single prescribed set uses the productive midpoint, not the lightest dose.
        if sets == 1 { return [midpoint(low: lo, high: hi)] }

        if hi - lo <= 2 {
            return topHeavyHold(low: lo, high: hi, count: sets)
        }
        return descending(from: hi, by: 2, count: sets, floor: lo)
    }

    /// Descends from `top` by `step` each set, clamped so it never drops below `floor`.
    private static func descending(from top: Int, by step: Int, count: Int, floor: Int) -> [Int] {
        (0..<count).map { i in max(floor, top - step * i) }
    }

    /// A heavy top-set hold: the first `ceil(count/2)` sets at `high`, the remainder
    /// at `low`. For a 3-rep-wide strength range this reads as `5,5,3` / `5,5,3,3`.
    private static func topHeavyHold(low: Int, high: Int, count: Int) -> [Int] {
        let topSets = Int(ceil(Double(count) / 2.0))
        return (0..<count).map { $0 < topSets ? high : low }
    }

    private static func midpoint(low: Int, high: Int) -> Int {
        clamp(Int((Double(low + high) / 2).rounded()), low: low, high: high)
    }

    private static func clamp(_ value: Int, low: Int, high: Int) -> Int {
        min(high, max(low, value))
    }
}
