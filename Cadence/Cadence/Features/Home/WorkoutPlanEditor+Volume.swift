import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension WorkoutPlanEditor {
    var startButton: some View {
        CadenceActionButton(title: "Start Workout", systemImage: "play.fill") {
            saveAndStart()
        }
        .accessibilityIdentifier("editor.start")
    }

    var settingsButton: some View {
        CadenceActionButton(title: "Show workout settings\u{2026}",
                            systemImage: "gearshape",
                            emphasis: .secondary) {
            settingsPresented = true
        }
        .accessibilityIdentifier("editor.showSettings")
    }

    /// Planned volume is intentionally cheap and synchronous: it only reduces
    /// the exercises currently being edited. This keeps typing, swapping, and
    /// changing set counts responsive.
    func refreshPlanVolume() {
        let prescriptions = plan.exercises.map { exercise in
            PlannedExercisePrescription(
                exerciseName: exercise.name,
                sets: exercise.sets.map { set in
                    PlannedSetPrescription(targetReps: set.targetReps,
                                            targetWeightKg: set.targetWeight)
                })
        }
        let planned = LiveWorkoutVolumeCalculator.plannedTotals(
            prescriptions, creditsByName: planVolumeCreditsByName())
        planVolumeState = LiveWorkoutVolumeState(current: planned,
                                                 weekly: planVolumeWeekly,
                                                 planned: [:])
    }

    /// Only the current training week is fetched. The previous implementation
    /// observed every historical WorkoutSession and rescanned all its sets on
    /// every plan edit, which made the editor visibly draggy on real histories.
    func refreshPlanWeeklyVolume() {
        let weekStart = LiveWorkoutVolumeCalculator.weekStart()
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.deletedAt == nil && session.date >= weekStart
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        let weeklySets = sessions
            .filter(\.countsAsStrengthHistory)
            .flatMap(LiveWorkoutVolumeCalculator.sets(from:))
        Task.detached(priority: .userInitiated) {
            let weekly = LiveWorkoutVolumeCalculator.totals(weeklySets, since: weekStart)
            await MainActor.run {
                planVolumeWeekly = weekly
                refreshPlanVolume()
            }
        }
    }

    func planVolumeCreditsByName() -> [String: [MuscleGroup: Double]] {
        var result: [String: [MuscleGroup: Double]] = [:]
        for exercise in plan.exercises {
            let key = exercise.name.lowercased()
            result[key] = exerciseIndex[key]?.volumeCredits
                ?? ExerciseLibrary.template(matching: exercise.name)?.volumeCredits
                ?? [:]
        }
        return result
    }
}
