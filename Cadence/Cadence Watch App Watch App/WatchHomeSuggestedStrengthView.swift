import SwiftUI
import CadenceCore
import CadenceFeatures

/// Today's valid phone suggestion wins; otherwise calculate locally without
/// requiring the phone to be reachable.
struct WatchHomeSuggestedStrengthView: View {
    @Environment(WatchWorkoutManager.self) private var manager
    @Environment(AppSettings.self) private var settings
    @State private var launch: WatchLiftLaunch?
    @State private var citationIDs: [String] = []
    @State private var finished = false

    var body: some View {
        List {
            if let launch {
                Text(launch.title).font(.headline)
                ForEach(launch.exerciseNames, id: \.self) { Text($0).font(.footnote) }
                if !citationIDs.isEmpty {
                    WatchCoachLineView(line: WatchCoachLine(text: "Workout sources", citationIDs: citationIDs))
                }
                NavigationLink {
                    WatchStrengthView(title: launch.title, plannedExerciseNames: launch.exerciseNames,
                                      repLadder: launch.repLadder, planPayload: launch.planPayload)
                } label: { Label("Start Strength", systemImage: "play.fill") }
            } else if finished {
                Text("Couldn't generate a suggestion. Try again or use Quick Start.")
            } else {
                ProgressView("Generating suggestion…")
            }
        }
        .navigationTitle("Suggested")
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
                launch = WatchLiftLaunch(title: "Suggested Strength", exerciseNames: names, repLadder: [],
                    planPayload: WatchPlanPayload(title: "Suggested Strength",
                        strength: .init(exerciseNames: names, prescriptions: prescriptions)))
                citationIDs = option.citationIDs
            }
            finished = true
        }
    }
}
