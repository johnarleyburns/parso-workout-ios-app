import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// Today's valid phone suggestion wins; otherwise calculate locally without
/// requiring the phone to be reachable.
struct WatchHomeSuggestedStrengthView: View {
    @Environment(WatchWorkoutManager.self) private var manager
    @Environment(AppSettings.self) private var settings
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
                launch = synced
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
                launch = WatchLiftLaunch(title: "Personalized Strength", exerciseNames: names, repLadder: [],
                    planPayload: WatchPlanPayload(title: "Personalized Strength",
                        strength: .init(exerciseNames: names, prescriptions: prescriptions)))
                citationIDs = option.citationIDs
            }
            finished = true
        }
    }
}
