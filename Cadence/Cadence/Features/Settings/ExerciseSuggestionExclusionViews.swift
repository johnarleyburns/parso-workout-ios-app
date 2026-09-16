import SwiftUI
import SwiftData
import CadenceCore

struct ExerciseSuggestionExclusionSheet: View {
    let exercise: Exercise
    /// Called right after the exclusion is durably saved, before the sheet
    /// dismisses. The suggested-workout plan editor uses this to regenerate
    /// the whole plan in place (real report: excluding an exercise left it
    /// sitting right there in the plan, since exclusion previously only
    /// affected *future* suggestion runs); every other call site (Settings,
    /// a manually-built or saved-routine plan) leaves this `nil` and keeps
    /// the previous behavior.
    var onExcluded: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var reason: ExerciseSuggestionExclusionReason = .personalPreference
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This affects future automatically generated suggestions only. It will not delete the exercise, change past workouts, or remove it from manual plans.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Don't Suggest \(exercise.name)")
                }

                Section("Why don't you want this suggested?") {
                    Picker("Reason", selection: $reason) {
                        ForEach(ExerciseSuggestionExclusionReason.allCases) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    .pickerStyle(.inline)
                    .accessibilityIdentifier("exclude.reason")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Exclude Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Exclude") { exclude() }
                        .bold()
                        .accessibilityIdentifier("exclude.confirm")
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func exclude() {
        do {
            try ExerciseSuggestionExclusionStore.setExcluded(exercise: exercise,
                                                              reason: reason,
                                                              in: context)
            onExcluded?()
            dismiss()
        } catch {
            errorMessage = "Could not save this preference: \(error.localizedDescription)"
        }
    }
}

struct ExcludedExercisesView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<ExerciseSuggestionExclusion> { $0.isActive },
           sort: [SortDescriptor(\ExerciseSuggestionExclusion.exerciseNameSnapshot)])
    private var exclusions: [ExerciseSuggestionExclusion]
    @Query(sort: [SortDescriptor(\Exercise.name)]) private var exercises: [Exercise]

    @State private var searchText = ""
    @State private var addPresented = false
    @State private var selectedExercise: Exercise?

    private var filteredExclusions: [ExerciseSuggestionExclusion] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return exclusions }
        return exclusions.filter {
            $0.exerciseNameSnapshot.lowercased().contains(query)
                || $0.reason.displayName.lowercased().contains(query)
        }
    }

    var body: some View {
        List {
            if filteredExclusions.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Excluded Exercises" : "No Matching Exercises",
                    systemImage: "checkmark.circle",
                    description: Text(searchText.isEmpty
                        ? "When a suggestion is not right for you, choose Don't Suggest This Exercise."
                        : "Try another exercise name or reason."))
            } else {
                Section {
                    ForEach(filteredExclusions) { exclusion in
                        exclusionRow(exclusion)
                    }
                } footer: {
                    Text("Excluded exercises remain available for manual planning, exercise search, and workout logging. They are omitted only from automatically generated suggestions.")
                }
            }
        }
        .navigationTitle("Excluded Exercises")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addPresented = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add excluded exercise")
                .accessibilityIdentifier("settings.excludedExercises.add")
            }
        }
        .searchable(text: $searchText, prompt: "Search excluded exercises")
        .sheet(isPresented: $addPresented) {
            addExerciseSheet
        }
        .sheet(item: $selectedExercise) { exercise in
            ExerciseSuggestionExclusionSheet(exercise: exercise)
        }
        .accessibilityIdentifier("settings.excludedExercises")
    }

    private var addExerciseSheet: some View {
        NavigationStack {
            List {
                ForEach(exercises) { exercise in
                    let alreadyExcluded = exclusions.contains {
                        $0.exerciseKey == ExerciseSuggestionExclusionKey.forExercise(exercise)
                    }
                    Button {
                        selectedExercise = exercise
                        addPresented = false
                    } label: {
                        HStack {
                            Text(exercise.name)
                            Spacer()
                            if alreadyExcluded {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(alreadyExcluded)
                }
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { addPresented = false }
                }
            }
            .searchable(text: $searchText, prompt: "Search exercises")
        }
    }

    private func exclusionRow(_ exclusion: ExerciseSuggestionExclusion) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(exclusion.exerciseNameSnapshot)
                Text(exclusion.reason.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Allow") {
                try? ExerciseSuggestionExclusionStore.allow(exclusion, in: context)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tint)
            .accessibilityIdentifier("settings.excludedExercises.allow.\(exclusion.exerciseNameSnapshot)")
        }
    }
}
