import SwiftUI
import CadenceCore
import CadenceFeatures

extension WorkoutPlanEditor {
    var addExerciseButton: some View {
        CadenceActionButton(title: "Add Exercise",
                            systemImage: "plus.circle.fill",
                            emphasis: .secondary) {
            exercisePickerIntent = .add
        }
        .accessibilityIdentifier("editor.addExercise")
    }

    func removeExercise(id: UUID) {
        plan.exercises.removeAll { $0.id == id }
    }

    var suggestExerciseButton: some View {
        CadenceActionButton(title: "Suggest Exercise…",
                            systemImage: "wand.and.stars",
                            emphasis: .secondary) {
            do {
                suggestExerciseRequest = try SuggestedExerciseRequestFactory.make(
                    context: modelContext,
                    settings: settings,
                    style: plan.suggestedWorkoutStyle ?? .fitness,
                    existingExerciseNames: plan.exercises.map(\.name),
                    alreadyAllocatedByMuscle: planAllocatedVolume())
            } catch {
                suggestExerciseFailed = true
            }
        }
        .accessibilityIdentifier("editor.suggestExercise")
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
        if !isEditing { isEditing = true }
        plan.exercises.append(EditableExercise(name: suggestion.name, sets: sets, notes: ""))
        resolvePartnerPlans()
    }
}
