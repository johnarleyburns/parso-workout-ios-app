import Foundation
import CadenceCore

/// One formatter for a *planned* set line, shared by the plan editor's compact
/// row and its per-performer lines (field test 2026-08-18 #4). Phase 4's
/// `WorkoutSummaryPresenter` formats *logged* sets; this is its planned twin, so
/// "80 kg×8" cannot drift between the two surfaces of the same plan.
public enum PlanFormatting {

    /// `80 kg×8`, `BW×12`, or `—×10`. `BW` is a statement about the movement,
    /// never about missing data (decision **D4**): a loaded lift with no
    /// resolvable target renders an em dash.
    public static func setLine(targetReps: Int,
                               targetWeightKg: Double?,
                               isBodyweight: Bool,
                               unit: MeasurementUnitPreference) -> String {
        if let weight = targetWeightKg {
            return "\(Format.weightValue(weight, unit: unit))×\(targetReps)"
        }
        return isBodyweight ? "BW×\(targetReps)" : "—×\(targetReps)"
    }

    /// The load half alone, with its unit — `80 kg`, `BW`, or `—`. Same D4 rule
    /// as `setLine`, for surfaces that show reps in their own control.
    public static func loadLabel(targetWeightKg: Double?,
                                 isBodyweight: Bool,
                                 unit: MeasurementUnitPreference) -> String {
        if let weight = targetWeightKg { return Format.weight(weight, unit: unit) }
        return isBodyweight ? "BW" : "—"
    }

    /// `80 kg×8  ·  85 kg×6  ·  90 kg×5` — one performer's whole exercise.
    public static func setsLine(_ sets: [EditableSet],
                                isBodyweight: Bool,
                                unit: MeasurementUnitPreference,
                                separator: String = "  ·  ") -> String {
        sets.map {
            setLine(targetReps: $0.targetReps, targetWeightKg: $0.targetWeight,
                    isBodyweight: isBodyweight, unit: unit)
        }
        .joined(separator: separator)
    }

    /// The performer plans to render, "Me" first, then partners in roster order.
    /// Returns `[]` for a solo exercise so the caller keeps its single line.
    public static func orderedPerformerPlans(_ exercise: EditableExercise) -> [EditablePerformerPlan] {
        guard exercise.performerPlans.count > 1 else { return [] }
        return exercise.performerPlans.filter(\.isMe) + exercise.performerPlans.filter { !$0.isMe }
    }
}
