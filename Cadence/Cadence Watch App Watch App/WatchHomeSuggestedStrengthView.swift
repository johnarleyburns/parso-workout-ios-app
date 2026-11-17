import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// Today's valid phone suggestion wins; otherwise calculate locally without
/// requiring the phone to be reachable.
struct WatchHomeSuggestedStrengthView: View {
    @Environment(WatchWorkoutManager.self) private var manager
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @State private var launch: WatchLiftLaunch?
    @State private var citationIDs: [String] = []
    @State private var finished = false

    var body: some View {
        Group {
            if let launch {
                WatchStrengthPreview(launch: launch, citationIDs: citationIDs)
            } else if finished {
                Text("Couldn't create a personalized workout. Try again or use Custom.")
            } else {
                ProgressView("Preparing personalized workout…")
            }
        }
        .navigationTitle("Personalized")
        .task {
            let ready = WatchSuggestResolver.resolve(envelope: manager.coachSuggestionEnvelope,
                now: manager.coachClock(), historyState: manager.coachHistoryState)
            if let synced = ready.launch {
                launch = prefilled(synced)
                finished = true
                return
            }
            let stored = WatchSingleExerciseSuggestionContextStore().load()
            let input = stored.flatMap {
                WatchSingleExerciseSuggestionAssembler.make(context: $0, activeExerciseNames: [],
                    activeWorkingSets: [], transientExcludedCandidateIDs: [])
            } ?? SuggestedWorkoutInput(completedSetsByMuscle: [:],
                candidates: ExerciseLibrary.starter.map(SuggestedExerciseCandidate.init(template:)),
                preferredSetsPerExercise: settings.coachSchedulePreferences.desiredSetsPerExercise,
                trainingGoal: settings.trainingGoal)
            let option = await Task.detached(priority: .userInitiated) {
                SuggestedWorkoutGenerator.generate(input: input).options.first
            }.value
            guard !Task.isCancelled else { return }
            if let option, !option.exercises.isEmpty {
                let names = option.exercises.map(\.name)
                let prescriptions = option.exercises.map { exercise in
                    PlannedExercisePrescription(exerciseName: exercise.name,
                        sets: (0..<exercise.plannedSets).map { _ in
                            PlannedSetPrescription(targetReps: exercise.repRange.lowerBound)
                        })
                }
                let generated = WatchLiftLaunch(title: "Personalized Strength", exerciseNames: names, repLadder: [],
                    planPayload: WatchPlanPayload(title: "Personalized Strength",
                        strength: .init(exerciseNames: names, prescriptions: prescriptions)))
                launch = prefilled(generated)
                citationIDs = option.citationIDs
            }
            finished = true
        }
    }
    private func prefilled(_ source: WatchLiftLaunch) -> WatchLiftLaunch {
        let exercises = (try? WorkoutRepository.allExercises(context)) ?? []
        let synced = WatchSetDefaultSnapshotPersistence().load()
        return WatchStrengthPreviewSetup.prefilledSuggestion(source) { name in
            let local = exercises.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                .map { WorkoutRepository.lastTimeSets(for: $0, performedBy: nil, excluding: nil)
                    .filter { !$0.isWarmup } } ?? []
            if !local.isEmpty {
                return .init(lastSets: local.map { .init(weightKg: $0.weight, reps: $0.reps) })
            }
            if let last = synced?.history(exerciseKey: name, performerID: "owner").lastPriorWorkingSet {
                return .init(lastSets: [.init(weightKg: last.weight, reps: last.reps)])
            }
            return .empty
        }
    }

}
