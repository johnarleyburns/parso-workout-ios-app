import Foundation
import CadenceCore

/// Pure readouts for the Progress screen (test-pyramid Phase 1): the estimated-1RM
/// series, its VoiceOver summary, and the goal-relative intensity/effort prose.
/// Moved out of `TrainingProgressView` so the copy rules are unit-tested instead
/// of asserted through XCUITest. The view keeps its Charts + `Color` rendering.
public enum ProgressPresenter {

    /// Best estimated-1RM series for the top lifts. `StrengthProgress.series`
    /// already excludes soft-deleted sessions.
    public static func strengthSeries(sessions: [WorkoutSession],
                                      formula: OneRepMaxFormula) -> [E1RMSeries] {
        StrengthProgress.series(from: sessions, formula: formula)
    }

    /// Signed textual delta for one lift, e.g. "up 5 kg" / "no change".
    public static func trendLabel(_ t: TrendDirection, delta: Double,
                                  unit: MeasurementUnitPreference) -> String {
        switch t {
        case .rising: return "up \(Format.weight(abs(delta), unit: unit, decimals: 0))"
        case .declining: return "down \(Format.weight(abs(delta), unit: unit, decimals: 0))"
        case .flat: return "no change"
        }
    }

    /// One-line VoiceOver summary of the (visually hidden) e1RM chart.
    public static func strengthTrendSummary(series: [E1RMSeries],
                                            unit: MeasurementUnitPreference) -> String {
        let tracked = series.filter { $0.points.count >= 2 }
        guard !tracked.isEmpty else { return "No lifts tracked yet." }
        let parts = tracked.map { "\($0.exercise) \(trendLabel($0.trend, delta: $0.delta, unit: unit))" }
        return "\(tracked.count) lifts tracked. " + parts.joined(separator: ", ")
    }

    /// Goal-relative read of the heavy/moderate/light load split.
    public static func intensityRead(_ i: IntensityDistribution, goal: TrainingGoal) -> String {
        switch goal {
        case .strength:
            return i.heavy >= 0.5 ? "Skewed to heavy loads \u{2014} aligned with a strength goal."
                                  : "Lighter than a strength goal usually calls for."
        case .hypertrophy:
            return i.moderate >= 0.5 ? "Mostly moderate-load work \u{2014} matched to the hypertrophy rep range."
                                     : "Spread across loads \u{2014} hypertrophy favors more moderate-rep work."
        case .endurance:
            return i.light >= 0.4 ? "Plenty of higher-rep work \u{2014} aligned with an endurance goal."
                                  : "Heavier than an endurance goal usually calls for."
        }
    }

    /// Goal-relative read of average reps-in-reserve.
    public static func effortRead(_ rir: Double, goal: TrainingGoal) -> String {
        let target = Double(goal.targetRIR)
        if rir <= target + 0.5 && rir >= target - 0.5 { return "In the effective range for \(goal.displayName.lowercased())." }
        return rir > target ? "A little further from failure than \(goal.displayName.lowercased()) calls for."
                            : "Closer to failure than \(goal.displayName.lowercased()) usually needs."
    }
}
