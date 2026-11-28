import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// Per-set `reps × load` lines for the Lift review screen. In their own file so
/// the preview view stays inside the type-checker and file-size budgets.
extension WatchStrengthPreview {
    /// One line per prescribed set: reps × load, so the reviewed targets are the
    /// ones Start carries. Kept out of `body` to stay inside the type-checker's
    /// budget.
    @ViewBuilder
    func setLines(for name: String) -> some View {
        let prepared = setup.preparedLaunch(from: launch)
        if let prescription = prepared.planPayload?.strength?.prescriptions.first(where: {
            $0.exerciseName.caseInsensitiveCompare(name) == .orderedSame
        }) {
            ForEach(Array(prescription.sets.enumerated()), id: \.offset) { _, set in
                Text(verbatim: "\(set.targetReps) × \(loadLabel(targetWeightKg: set.targetWeightKg, name: name))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if !prepared.repLadder.isEmpty {
            Text(verbatim: prepared.repLadder.map(String.init).joined(separator: "-"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    func loadLabel(targetWeightKg: Double?, name: String) -> String {
        if let targetWeightKg { return Format.weight(targetWeightKg, unit: settings.unit) }
        return ExerciseLoading.isBodyweight(named: name) ? "BW" : "—"
    }
}
