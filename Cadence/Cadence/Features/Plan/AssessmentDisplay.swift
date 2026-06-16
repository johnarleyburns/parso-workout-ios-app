import SwiftUI
import CadenceCore

/// View-layer formatting for assessments (strength-pivot P4). Keeps the unit-aware
/// rendering of reps / hold-times / canonical-kg weights out of the views.
enum AssessmentDisplay {

    /// A result value rendered in its kind's unit: "32 reps", "1:30", "100 kg".
    static func value(_ value: Double, kind: AssessmentKind, unit: MeasurementUnitPreference) -> String {
        switch kind.unit {
        case .reps:
            return "\(Int(value.rounded())) reps"
        case .seconds:
            return Format.duration(value)
        case .weightKg:
            return Format.weight(value, unit: unit, decimals: 0)
        }
    }

    /// Short label for a series row, e.g. "Bench press 1RM" or "Max push-ups".
    static func seriesTitle(_ summary: AssessmentSummary) -> String {
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

extension AssessmentTrend {
    var symbol: String {
        switch self {
        case .improved: return "arrow.up.right"
        case .declined: return "arrow.down.right"
        case .unchanged: return "equal"
        case .single: return "circle"
        }
    }
    var tint: Color {
        switch self {
        case .improved: return .green
        case .declined: return .orange
        case .unchanged, .single: return .secondary
        }
    }
    var label: String {
        switch self {
        case .improved: return "Improving"
        case .declined: return "Down"
        case .unchanged: return "Holding"
        case .single: return "Baseline"
        }
    }
}
