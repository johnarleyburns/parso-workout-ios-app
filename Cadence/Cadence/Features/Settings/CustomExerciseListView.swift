import SwiftUI
import SwiftData
import CadenceCore

struct CustomExerciseListView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Exercise> { $0.isCustom }, sort: \Exercise.name) private var customExercises: [Exercise]
    @Query(filter: #Predicate<Exercise> { !$0.isCustom }, sort: \Exercise.name) private var builtIns: [Exercise]

    @State private var editExercise: Exercise?
    @State private var deleteTarget: Exercise?
    @State private var reassignSheet = false

    private var incomplete: [Exercise] {
        customExercises.filter { $0.primaryMuscles.isEmpty }
    }

    private var complete: [Exercise] {
        customExercises.filter { !$0.primaryMuscles.isEmpty }
    }

    private func bestMatch(for custom: Exercise) -> Exercise? {
        let normalized = ExerciseSearch.normalize(custom.name)
        let candidates = builtIns.filter { ex in
            let exName = ExerciseSearch.normalize(ex.name)
            guard exName != normalized else { return false }
            return exName.contains(normalized) || normalized.contains(exName)
        }
        if candidates.count == 1 { return candidates[0] }
        if candidates.count > 1 {
            return ExerciseSearchIndex(candidates).rank(custom.name).first
        }
        return nil
    }

    var body: some View {
        List {
            if !incomplete.isEmpty {
                Section("Needs Definition — \(incomplete.count) exercise\(incomplete.count == 1 ? "" : "s")") {
                    ForEach(incomplete) { ex in
                        incompleteRow(for: ex)
                    }
                }
            }

            if !complete.isEmpty {
                Section("Defined — \(complete.count) exercise\(complete.count == 1 ? "" : "s")") {
                    ForEach(complete) { ex in
                        row(for: ex)
                    }
                }
            }

            if customExercises.isEmpty {
                ContentUnavailableView("No Custom Exercises",
                                        systemImage: "figure.strengthtraining.traditional",
                                        description: Text("Create custom exercises from the workout picker."))
            }
        }
        .navigationTitle("Custom Exercises")
        .sheet(item: $editExercise) { exercise in
            CustomExerciseEditView(exercise: exercise) { editExercise = nil }
        }
        .sheet(isPresented: $reassignSheet) {
            if let target = deleteTarget {
                ReassignExercisePickerView(customExercise: target) { builtIn in
                    _ = try? WorkoutRepository.reassignAndDeleteExercise(from: target, into: builtIn, in: context)
                    reassignSheet = false
                    deleteTarget = nil
                }
            }
        }
    }

    private func incompleteRow(for ex: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ex.name).font(.body.weight(.medium))
                    Text("No muscles set")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if let match = bestMatch(for: ex) {
                HStack {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text("Matches: ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(match.name)
                        .font(.caption.weight(.medium))
                    Spacer()
                }
                .padding(.top, 2)
            }

            HStack(spacing: 8) {
                Button { editExercise = ex } label: {
                    Label("Define", systemImage: "pencil")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered).controlSize(.small)

                if bestMatch(for: ex) != nil {
                    Button("Reassign") {
                        deleteTarget = ex
                        reassignSheet = true
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func row(for ex: Exercise) -> some View {
        Button { editExercise = ex } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ex.name).font(.body.weight(.medium))

                    HStack(spacing: 6) {
                        if let cat = ex.categoryValue {
                            Text(cat.displayName)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(categoryColor(cat).opacity(0.15), in: Capsule())
                                .foregroundStyle(categoryColor(cat))
                        }

                        ForEach(Array(BodyPart.parts(forMuscleIDs: ex.primaryMuscles).sorted { $0.rawValue < $1.rawValue }.prefix(3)), id: \.self) { part in
                            Text(part.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func categoryColor(_ cat: ExerciseCategory) -> Color {
        switch cat {
        case .push: return .blue
        case .pull: return .green
        case .legs: return .orange
        case .core: return .purple
        default: return .secondary
        }
    }
}

private struct ReassignExercisePickerView: View {
    let customExercise: Exercise
    let onPick: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Exercise> { !$0.isCustom }, sort: \Exercise.name) private var builtIns: [Exercise]

    private var suggestedCategory: ExerciseCategory? {
        customExercise.categoryValue ?? BodyPart.guessCategory(from: customExercise.name)
    }

    private var suggestions: [Exercise] {
        guard let cat = suggestedCategory else { return Array(builtIns.prefix(20)) }
        return builtIns.filter { $0.categoryValue == cat }
    }

    private var others: [Exercise] {
        let suggestionIDs = Set(suggestions.map(\.id))
        return builtIns.filter { !suggestionIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !suggestions.isEmpty {
                    Section("Suggested") {
                        ForEach(suggestions) { ex in
                            Button { onPick(ex); dismiss() } label: {
                                HStack {
                                    Text(ex.name)
                                    Spacer()
                                    if let cat = ex.categoryValue {
                                        Text(cat.displayName)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !others.isEmpty {
                    Section("All Built-In") {
                        ForEach(others) { ex in
                            Button { onPick(ex); dismiss() } label: {
                                HStack {
                                    Text(ex.name)
                                    Spacer()
                                    if let cat = ex.categoryValue {
                                        Text(cat.displayName)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Reassign to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
