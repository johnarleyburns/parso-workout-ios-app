import Foundation

/// Pure helpers for heart-rate sample series (feedback batch 4 — recorded Watch
/// HR ingestion). Keeps stored curves light and the logic unit-testable.
public enum HRSampling {

    /// Default cap on stored HR points — enough to draw a smooth curve without
    /// bloating the local store / CloudKit payload for long workouts.
    public static let defaultMaxPoints = 120

    /// Reduces a sample series to at most `maxPoints`, preserving chronological
    /// order plus the first and last points. Uniform stride decimation: cheap,
    /// deterministic, and good enough for a summary chart. Samples are sorted by
    /// time first; an already-small series is returned (sorted) unchanged.
    public static func downsample(_ samples: [HRSamplePoint],
                                  maxPoints: Int = defaultMaxPoints) -> [HRSamplePoint] {
        let sorted = samples.sorted { $0.t < $1.t }
        guard maxPoints >= 2, sorted.count > maxPoints else { return sorted }

        // Pick indices on an even stride across the series, always keeping the
        // last sample so the curve ends where the workout did.
        var picked: [HRSamplePoint] = []
        picked.reserveCapacity(maxPoints)
        let stride = Double(sorted.count - 1) / Double(maxPoints - 1)
        var lastIndex = -1
        for i in 0..<maxPoints {
            let idx = Int((Double(i) * stride).rounded())
            if idx != lastIndex {
                picked.append(sorted[idx])
                lastIndex = idx
            }
        }
        if let last = sorted.last, picked.last?.t != last.t { picked.append(last) }
        return picked
    }
}
