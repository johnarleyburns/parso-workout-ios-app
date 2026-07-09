import Foundation

/// Predicts the next rep count when adding a set, based on patterns in the
/// user's prior workout history. Runs headlessly in `swift test`.
public enum RepPattern {

    /// Guesses the rep count for set index `setIndex` (0-based) given the
    /// current session's prior sets and the rep ladders from prior sessions
    /// (one array per session, oldest first or any order). Returns nil when
    /// no confident prediction can be made.
    ///
    /// Priority:
    /// 1. Session-in-progress: if the first N reps match a known pattern's
    ///    prefix, use that pattern's Nth value.
    /// 2. Flat detection: if all current reps are the same value, repeat it.
    /// 3. Arithmetic progression: if the current session shows a clear
    ///    ascending/descending step, extrapolate.
    /// 4. Prior session consensus: if >50% of prior sessions use the same
    ///    rep ladder, use that ladder's setIndex value.
    public static func guess(
        setIndex: Int,
        currentSessionReps: [Int],
        priorSessionLadders: [[Int]]
    ) -> Int? {
        guard setIndex >= 0 else { return nil }
        guard setIndex >= currentSessionReps.count else {
            return currentSessionReps[setIndex]
        }

        let n = currentSessionReps.count

        // No history at all — nothing to base a guess on.
        if n == 0 && priorSessionLadders.isEmpty { return nil }

        // If we have session-in-progress data, try to match against prior
        // patterns that start the same way.
        if n > 0, !priorSessionLadders.isEmpty {
            let matchingPrior = priorSessionLadders.filter { ladder in
                ladder.count > setIndex && (0..<min(n, ladder.count)).allSatisfy { i in
                    ladder[i] == currentSessionReps[i]
                }
            }
            if let best = mostCommonLadder(in: matchingPrior, minLength: setIndex + 1),
               best.count > setIndex {
                return best[setIndex]
            }
            // If exactly one prior session has a matching prefix, use it.
            if matchingPrior.count == 1,
               let first = matchingPrior.first,
               first.count > setIndex {
                return first[setIndex]
            }
        }

        // Flat detection: all reps identical.
        if n >= 2, Set(currentSessionReps).count == 1 {
            return currentSessionReps[0]
        }

        // Arithmetic progression: constant step between consecutive reps.
        if n >= 2 {
            let deltas = zip(currentSessionReps, currentSessionReps.dropFirst()).map { $1 - $0 }
            let uniqueDeltas = Set(deltas)
            if uniqueDeltas.count == 1, let delta = uniqueDeltas.first {
                let predicted = currentSessionReps.last! + delta
                if predicted >= 1 { return predicted }
            }
        }

        // Prior session consensus: most common ladder wins if it has
        // coverage for the target set index.
        if let best = mostCommonLadder(in: priorSessionLadders, minLength: setIndex + 1) {
            let confidence = Double(
                priorSessionLadders.filter { $0 == best }.count
            ) / Double(priorSessionLadders.count)
            if confidence > 0.5 {
                return best[setIndex]
            }
        }

        // Last resort: if prior sessions exist, use the most recent one's
        // value at this set index.
        if let last = priorSessionLadders.last, last.count > setIndex {
            return last[setIndex]
        }

        return nil
    }

    /// Returns the most frequent ladder in `ladders` whose length is at
    /// least `minLength`. Ties go to the first encountered (arbitrary but
    /// stable per input ordering).
    private static func mostCommonLadder(
        in ladders: [[Int]],
        minLength: Int
    ) -> [Int]? {
        let candidates = ladders.filter { $0.count >= minLength }
        guard !candidates.isEmpty else { return nil }
        var counts: [[Int]: Int] = [:]
        for l in candidates { counts[l, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}
