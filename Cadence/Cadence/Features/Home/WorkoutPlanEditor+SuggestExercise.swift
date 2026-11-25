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

    func planAllocatedVolume() -> [String: Double] {
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
        // Keep the new row consistent with the user's real history, exactly as
        // the initial generated plan does.
        seededHistoryNames.remove(suggestion.name)
        seedMissingSuggestedHistory()
        seedPlanWeights()
        resolvePartnerPlans()
        seedPlanWeights()
    }

    /// Excluding a movement from a saved or custom plan used to only affect
    /// future suggestions, so the row stayed exactly as it was. Ask the same
    /// single-exercise solver the Add Exercise sheet uses for a replacement
    /// that fits the remaining allocation, then swap it into the same slot.
    @MainActor
    func replaceExcludedExercise(rowID: UUID) async {
        guard plan.exercises.contains(where: { $0.id == rowID }) else { return }
        isRegeneratingAfterExclusion = true
        defer { isRegeneratingAfterExclusion = false }
        let request: SuggestedExerciseRequest
        do {
            request = try SuggestedExerciseRequestFactory.make(
                context: modelContext,
                settings: settings,
                style: .personalized,
                existingExerciseNames: plan.exercises.map(\.name),
                alreadyAllocatedByMuscle: planAllocatedVolume())
        } catch {
            regenerationFailed = true
            return
        }
        let input = request.input
        let style = request.style
        let allocated = request.alreadyAllocatedByMuscle
        let excluded = request.excludingCandidateIDs
        let priority = request.priorityMuscle
        let replacement = await Task.detached(priority: .userInitiated) {
            SuggestedWorkoutGenerator.suggestSingleExercise(
                input: input,
                style: style,
                alreadyAllocatedByMuscle: allocated,
                excludingCandidateIDs: excluded,
                allowPersonalizedFallback: true,
                priorityMuscle: priority)
        }.value
        guard let replacement,
              let index = plan.exercises.firstIndex(where: { $0.id == rowID }) else {
            regenerationFailed = true
            return
        }
        plan.exercises[index].name = replacement.name
        // The replacement has its own history; never inherit the excluded
        // movement's loads.
        plan.exercises[index].sets = plan.exercises[index].sets.map { set in
            guard set.loadMode == .straight else { return set }
            var updated = set
            updated.targetWeight = nil
            return updated
        }
        seededHistoryNames.remove(replacement.name)
        seedMissingSuggestedHistory()
        seedPlanWeights()
        resolvePartnerPlans()
        seedPlanWeights()
    }
}
