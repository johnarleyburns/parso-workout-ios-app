import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// Presentation hooks supplied ONLY by the suggested-strength preview sheet.
/// When nil (every other editor flow) the editor's actions and dismissal are
/// unchanged. The plan passed to each closure is the user's current edit.
struct SuggestedStrengthEditorHooks {
    var isRegenerating: Bool
    var message: String?
    var onStart: (EditablePlan) -> Void
    var onScheduled: () -> Void
    var onSuggestAnother: (EditablePlan) -> Void
    var onCancel: () -> Void
}

extension WorkoutPlanEditor {
    var startButton: some View {
        CadenceActionButton(title: String(localized: "Start Workout"), systemImage: "play.fill") {
            saveAndStart()
        }
        .accessibilityIdentifier("editor.start")
    }

    /// Start / Schedule / Suggest another, in that order. Cancel is rendered
    /// last, below all plan content, by the editor body.
    @ViewBuilder var suggestedStrengthActions: some View {
        if let hooks = suggestedStrength {
            CadenceActionButton(title: String(localized: "Start this Workout"), systemImage: "play.fill") {
                saveAndStart()
            }
            .disabled(hooks.isRegenerating)
            .accessibilityIdentifier(SuggestedStrengthActionContract.startIdentifier)
            CadenceActionButton(title: String(localized: "Schedule this Workout"),
                                systemImage: "calendar.badge.plus",
                                emphasis: .secondary) {
                if isEditing {
                    originalPlan = plan
                    isEditing = false
                }
                schedulePresented = true
            }
            .disabled(hooks.isRegenerating)
            .accessibilityIdentifier(SuggestedStrengthActionContract.scheduleIdentifier)
            CadenceActionButton(title: String(localized: "Suggest another"),
                                systemImage: "arrow.triangle.2.circlepath",
                                emphasis: .secondary) {
                hooks.onSuggestAnother(plan)
            }
            .disabled(hooks.isRegenerating)
            .accessibilityIdentifier(SuggestedStrengthActionContract.anotherIdentifier)
            if hooks.isRegenerating {
                ProgressView(String(localized: "Finding another workout\u{2026}"))
                    .accessibilityIdentifier("suggestedStrength.loading")
            }
            if let message = hooks.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("suggestedStrength.message")
            }
        }
    }

    /// Text-only, visually secondary, below all plan content.
    @ViewBuilder var suggestedStrengthCancel: some View {
        if let hooks = suggestedStrength {
            Button(String(localized: "Cancel")) { hooks.onCancel() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier(SuggestedStrengthActionContract.cancelIdentifier)
        }
    }

    var sendToWatchButton: some View {
        CadenceActionButton(title: String(localized: "Send Workout to Watch"),
                            systemImage: "applewatch",
                            emphasis: .secondary) {
            sendToWatch()
        }
        .accessibilityHint(String(localized: "Puts this workout on your Apple Watch under Sent from your phone. You start it there."))
        .accessibilityIdentifier("editor.sendToWatch")
    }

    func sendToWatch() {
        let exercises = plan.exercises.map { (name: $0.name, repTargets: $0.sets.map(\.targetReps)) }
        let workout = WatchSentWorkouts.strengthSession(
            title: plan.title.isEmpty ? String(localized: "Workout") : plan.title,
            exercises: exercises)
        sendToWatchSucceeded = model.sendWorkoutToWatch(workout)
        sendToWatchResultPresented = true
    }

    var scheduleButton: some View {
        CadenceActionButton(title: String(localized: "Schedule this Workout"),
                            systemImage: "calendar.badge.plus",
                            emphasis: .secondary) {
            if isEditing {
                originalPlan = plan
                isEditing = false
            }
            schedulePresented = true
        }
        .accessibilityIdentifier("editor.schedule")
    }

    var settingsButton: some View {
        CadenceActionButton(title: String(localized: "Show workout settings\u{2026}"),
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
        let credits = planVolumeCreditsByName()
        var performers: [VolumeSummaryPerformer] = [.owner]
        for id in plan.partnerIDs {
            let name = allPeople.first(where: { $0.id == id })?.name ?? String(localized: "Partner")
            performers.append(VolumeSummaryPerformer(id: id.uuidString,
                                                     name: name,
                                                     personID: id))
        }
        let prescriptionsByPerformer = Dictionary(uniqueKeysWithValues:
            plan.performerPrescriptions().map { prescription in
                (prescription.performerID ?? VolumeSummaryPerformer.ownerKey,
                 prescription.exercises)
            })
        var states: [String: LiveWorkoutVolumeState] = [:]
        for performer in performers {
            let planned = LiveWorkoutVolumeCalculator.plannedTotals(
                prescriptionsByPerformer[performer.id] ?? prescriptions,
                creditsByName: credits)
            states[performer.id] = LiveWorkoutVolumeState(
                current: [:],
                weekly: performer.isOwner ? planVolumeWeekly : [:],
                planned: planned)
        }
        planVolumePerformers = performers
        planVolumePerformerStates = states
        planVolumeState = states[VolumeSummaryPerformer.ownerKey] ?? LiveWorkoutVolumeState()
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
