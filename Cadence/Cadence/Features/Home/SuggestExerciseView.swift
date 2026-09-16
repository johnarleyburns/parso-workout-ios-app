import SwiftUI
import CadenceCore
import CadenceFeatures

private enum SingleExerciseSuggestionState {
    case calculating
    case ready(SuggestedWorkoutExercise)
    case failed(String)
}

/// The one-movement version of the suggested-workout surface. It deliberately
/// has one calculation path for plan editing and live workouts, so a movement
/// added in either place respects the same exclusions and allocation math.
struct SuggestExerciseView: View {
    let request: SuggestedExerciseRequest
    let exerciseForName: (String) -> Exercise?
    let onAdd: (SuggestedWorkoutExercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var state: SingleExerciseSuggestionState = .calculating
    @State private var excludedCandidateIDs: Set<String> = []
    @State private var exclusionExercise: Exercise?

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .calculating:
                    ProgressView("Finding a useful next exercise…")
                        .accessibilityIdentifier("suggestExercise.calculating")
                case .ready(let exercise):
                    result(exercise)
                case .failed(let message):
                    ContentUnavailableView("Couldn't suggest an exercise",
                                           systemImage: "dumbbell",
                                           description: Text(message))
                    Button("Try again") { Task { await calculate() } }
                        .accessibilityIdentifier("suggestExercise.retry")
                }
            }
            .navigationTitle("Suggest Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("suggestExercise.close")
                }
            }
        }
        .task { await calculate() }
        .sheet(item: $exclusionExercise) { exercise in
            ExerciseSuggestionExclusionSheet(exercise: exercise, onExcluded: {
                exclusionExercise = nil
                Task { await calculate() }
            })
        }
    }

    private func calculate() async {
        state = .calculating
        await Task.yield()
        guard !Task.isCancelled else { return }
        let input = request.input
        let style = request.style
        let allocated = request.alreadyAllocatedByMuscle
        let excluded = request.excludingCandidateIDs.union(excludedCandidateIDs)
        let result = await Task.detached(priority: .userInitiated) {
            SuggestedWorkoutGenerator.suggestSingleExercise(
                input: input,
                style: style,
                alreadyAllocatedByMuscle: allocated,
                excludingCandidateIDs: excluded)
        }.value
        guard !Task.isCancelled else { return }
        if let result {
            state = .ready(result)
        } else {
            state = .failed("No eligible movement remains after applying your workout, style, and suggestion preferences.")
        }
    }

    private func result(_ exercise: SuggestedWorkoutExercise) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(exercise.name).font(.title3.weight(.semibold))
                    Spacer()
                    if let info = exerciseForName(exercise.name) {
                        NavigationLink {
                            ExerciseDetailView(exercise: info)
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("suggestExercise.info")
                        .accessibilityLabel("Exercise details")
                    }
                }
                Text("\(exercise.plannedSets) sets · \(exercise.repRange.lowerBound)–\(exercise.repRange.upperBound) reps")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Selected for your \(request.style.displayName.lowercased()) workout using the remaining allocation in this workout.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !exercise.contributions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Primary focus").font(.headline)
                        ForEach(exercise.contributions, id: \.muscleID) { contribution in
                            HStack {
                                Text(displayName(contribution.muscleID))
                                Spacer()
                                Text("\(Int(contribution.weight * 100))%")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .green)
                }
                CadenceActionButton(title: "Add to Workout", systemImage: "plus.circle.fill") {
                    onAdd(exercise)
                    dismiss()
                }
                .accessibilityIdentifier("suggestExercise.add")
                CadenceActionButton(title: "Suggest another", systemImage: "arrow.clockwise",
                                    emphasis: .secondary) {
                    excludedCandidateIDs.insert(exercise.candidateID)
                    Task { await calculate() }
                }
                .accessibilityIdentifier("suggestExercise.another")
                if let info = exerciseForName(exercise.name) {
                    Button(role: .destructive) { exclusionExercise = info } label: {
                        Label("Don't suggest this exercise", systemImage: "hand.raised")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
                    .accessibilityIdentifier("suggestExercise.exclude")
                }
            }
            .padding()
        }
        .accessibilityIdentifier("suggestExercise.result")
    }

    private func displayName(_ id: String) -> String {
        id.replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}
