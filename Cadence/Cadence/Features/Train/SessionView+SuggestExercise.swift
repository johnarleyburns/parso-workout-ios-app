import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension SessionView {
    var suggestExerciseButton: some View {
        CadenceActionButton(title: String(localized: "Suggest Exercise…"),
                            systemImage: "wand.and.stars",
                            emphasis: .secondary) {
            do {
                suggestExerciseRequest = try SuggestedExerciseRequestFactory.make(
                    context: context,
                    settings: settings,
                    style: .personalized,
                    existingExerciseNames: sessionExerciseNames,
                    alreadyAllocatedByMuscle: activeAllocatedVolume(),
                    excludingSessionID: session.id)
            } catch {
                suggestExerciseFailed = true
            }
        }
        .accessibilityIdentifier("session.suggestExercise")
    }

    private var sessionExerciseNames: [String] {
        var names = session.plannedExerciseNames
        for exercise in session.exercisesInOrder where !names.contains(exercise.name) {
            names.append(exercise.name)
        }
        return names
    }

    /// Planned prescriptions are the allocation budget for a live workout. If
    /// an older/manual session has no prescriptions, its saved working sets are
    /// the best available budget instead.
    private func activeAllocatedVolume() -> [String: Double] {
        let sets = LiveWorkoutVolumeCalculator.totals(
            LiveWorkoutVolumeCalculator.sets(from: session))
        guard !session.plannedPrescriptions.isEmpty else {
            return sets.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value }
        }
        let planned = LiveWorkoutVolumeCalculator.plannedTotals(
            session.plannedPrescriptions, creditsByName: plannedCreditsByName())
        return planned.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value }
    }

    func addSuggestedExercise(_ suggestion: SuggestedWorkoutExercise) {
        guard let exercise = exerciseForName(named: suggestion.name)
                ?? (try? WorkoutRepository.findOrCreateExercise(named: suggestion.name,
                                                                 in: context)) else { return }
        if !sessionExerciseNames.contains(where: {
            $0.caseInsensitiveCompare(exercise.name) == .orderedSame
        }) {
            session.plannedExerciseNames.append(exercise.name)
            // Record the suggestion's set/rep prescription so the exercise's Add
            // Set action honors it, without opening the set editor (field report:
            // "Suggest Exercise" must return to the workout screen).
            var prescriptions = session.plannedPrescriptions
            if !prescriptions.contains(where: {
                $0.exerciseName.caseInsensitiveCompare(exercise.name) == .orderedSame
            }) {
                let sets = (0..<max(1, suggestion.plannedSets)).map { _ in
                    PlannedSetPrescription(targetReps: suggestion.repRange.lowerBound,
                                           targetWeightKg: nil)
                }
                prescriptions.append(PlannedExercisePrescription(exerciseName: exercise.name,
                                                                 sets: sets))
                session.plannedPrescriptions = prescriptions
            }
            try? context.save()
        }
        recordActivity()
    }

    func exerciseForName(named name: String) -> Exercise? {
        plannedExerciseIndex[name] ??
            (try? WorkoutRepository.allExercises(context).first {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            })
    }
}
