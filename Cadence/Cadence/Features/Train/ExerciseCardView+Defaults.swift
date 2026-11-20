import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

extension ExerciseCardView {
    /// Default load/reps for the next planned set, kept on the collapsed row so
    /// the athlete can read every exercise's starting numbers without expanding.
    var defaultsLine: String? {
        guard let pending = context.pendingSets.first else { return nil }
        if let kg = pending.targetWeightKg, kg > 0 {
            return "Next: \(Format.weightValue(kg, unit: unit)) \(unit.abbreviation) × \(pending.targetReps)"
        }
        return "Next: \(pending.targetReps) reps"
    }
}
