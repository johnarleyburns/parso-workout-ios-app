import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

extension WorkoutPlanEditor {
    /// The plan screen has one Add Exercise entry point. It opens the same
    /// suggestion surface as before, renamed to match what it does.
    var suggestExerciseButton: some View {
        CadenceActionButton(title: String(localized: "Add Exercise"),
                            systemImage: "plus.circle.fill",
                            emphasis: .secondary) {
            do {
                suggestExerciseRequest = try SuggestedExerciseRequestFactory.make(
                    context: modelContext,
                    settings: settings,
                    style: .personalized,
                    existingExerciseNames: plan.exercises.map(\.name),
                    alreadyAllocatedByMuscle: planAllocatedVolume())
            } catch {
                suggestExerciseFailed = true
            }
        }
        .accessibilityIdentifier("editor.addExercise")
    }

    private func planAllocatedVolume() -> [String: Double] {
        let prescriptions = plan.exercises.map { exercise in
            PlannedExercisePrescription(
                exerciseName: exercise.name,
                sets: exercise.sets.map { set in
                    PlannedSetPrescription(targetReps: set.targetReps,
                                            targetWeightKg: set.targetWeight)
                })
        }
        return LiveWorkoutVolumeCalculator.plannedTotals(
            prescriptions, creditsByName: planVolumeCreditsByName())
            .reduce(into: [:]) { $0[$1.key.rawValue] = $1.value }
    }

    func addSuggestedExercise(_ suggestion: SuggestedWorkoutExercise) {
        let sets = (0..<suggestion.plannedSets).map { _ in
            EditableSet(targetReps: suggestion.repRange.lowerBound, targetWeight: nil)
        }
        // Adding an exercise must never flip the plan into an editing mode.
        plan.exercises.append(EditableExercise(name: suggestion.name, sets: sets, notes: ""))
        seedPlanWeights()
        resolvePartnerPlans()
    }
}
