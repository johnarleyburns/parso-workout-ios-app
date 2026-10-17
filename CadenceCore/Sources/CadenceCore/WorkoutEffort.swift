import Foundation

/// Maps what Cladiron already knows about a finished workout onto Apple's
/// 1...10 workout effort score, which Apple Health uses for Training Load.
/// Returns nil (nothing is written) when there is no honest basis for a value.
public enum WorkoutEffort {
    public static let range: ClosedRange<Double> = 1...10

    /// Mean RPE of the logged working sets, clamped to 1...10.
    public static func strengthScore(workingSetRPEs: [Double]) -> Double? {
        let valid = workingSetRPEs.filter { $0 > 0 }
        guard !valid.isEmpty else { return nil }
        return clamp(valid.reduce(0, +) / Double(valid.count))
    }

    /// Cardio effort from the share of classified time spent at moderate and
    /// vigorous intensity: all-easy ≈ 3, all-moderate ≈ 6, all-vigorous ≈ 9.
    public static func cardioScore(_ minutes: CardioMinuteSummary?) -> Double? {
        guard let m = minutes, m.classifiedDuration > 0 else { return nil }
        let easy = max(0, m.classifiedDuration - m.moderateDuration - m.vigorousDuration)
        let weighted = easy * 3 + m.moderateDuration * 6 + m.vigorousDuration * 9
        return clamp(weighted / m.classifiedDuration)
    }

    private static func clamp(_ v: Double) -> Double {
        min(max(v, range.lowerBound), range.upperBound)
    }
}
