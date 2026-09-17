import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension SessionView {
    var suggestExerciseButton: some View {
        CadenceActionButton(title: "Suggest Exercise…",
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
            try? context.save()
        }
        openInlineEditor(for: exercise, repsOverride: suggestion.repRange.lowerBound)
    }

    func exerciseForName(named name: String) -> Exercise? {
        plannedExerciseIndex[name] ??
            (try? WorkoutRepository.allExercises(context).first {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            })
    }
}
