import Foundation
import CadenceCore

/// Pure display formatting for assessments (strength-pivot P4). Keeps the
/// unit-aware rendering of reps / hold-times / canonical-kg weights out of the
/// views. Moved from the app's `Features/Plan/AssessmentDisplay.swift`
/// (test-pyramid Phase 1); the `Color`/SF-Symbol mapping of `AssessmentTrend`
/// stays in the view layer.
public enum AssessmentDisplay {

    /// A result value rendered in its kind's unit: "32 reps", "1:30", "100 kg",
    /// "42.5 mL/kg/min", "850 W".
    public static func value(_ value: Double, kind: AssessmentKind, unit: MeasurementUnitPreference) -> String {
        switch kind.unit {
        case .reps:
            return "\(Int(value.rounded())) reps"
        case .seconds:
            return Format.duration(value)
        case .weightKg:
            return Format.weight(value, unit: unit, decimals: 0)
        case .mlKgMin:
            return "\(String(format: "%.1f", value)) mL/kg/min"
        case .watts:
            return "\(Int(value.rounded())) W"
        }
    }

    /// Short label for a series row, e.g. "Bench press 1RM" or "Max push-ups".
    public static func seriesTitle(_ summary: AssessmentSummary) -> String {
        if summary.kind.concernsLift, let lift = summary.exerciseName, !lift.isEmpty {
            switch summary.kind {
            case .e1RM: return "\(lift) 1RM"
            case .repMax: return "\(lift) rep-max"
            default: return summary.kind.displayName
            }
        }
        return summary.kind.displayName
    }
}
