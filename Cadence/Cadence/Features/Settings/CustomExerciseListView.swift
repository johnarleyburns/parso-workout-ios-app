import SwiftUI
import SwiftData
import CadenceCore

struct CustomExerciseListView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Exercise> { $0.isCustom }, sort: \Exercise.name) private var customExercises: [Exercise]

    @State private var editExercise: Exercise?
    @State private var deleteTarget: Exercise?
    @State private var reassignSheet = false

    var body: some View {
        List {
            if customExercises.isEmpty {
                ContentUnavailableView("No Custom Exercises",
                                        systemImage: "figure.strengthtraining.traditional",
                                        description: Text("Create custom exercises from the workout picker."))
            }
            ForEach(customExercises) { ex in
                row(for: ex)
                    .contextMenu {
                        Button { editExercise = ex } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            deleteTarget = ex
                            reassignSheet = true
                        } label: {
                            Label("Delete & reassign", systemImage: "arrow.triangle.swap")
                        }
                    }
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

                        let parts = BodyPart.parts(forMuscleIDs: ex.primaryMuscles)
                        if parts.isEmpty {
                            Text("Incomplete")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                                .foregroundStyle(.orange)
                        } else {
                            ForEach(Array(parts.sorted { $0.rawValue < $1.rawValue }.prefix(3)), id: \.self) { part in
                                Text(part.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
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
