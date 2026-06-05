import SwiftUI
import SwiftData
import CadenceCore

/// Searchable exercise library picker (FR-1.1). Groups by category and offers an
/// inline "Create '<query>'" row for custom exercises (UC-1 alternate 2a).
struct ExercisePickerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var query = ""
    let onPick: (Exercise) -> Void

    private var filtered: [Exercise] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return exercises }
        return exercises.filter { $0.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    private var grouped: [(ExerciseCategory, [Exercise])] {
        let dict = Dictionary(grouping: filtered) { $0.categoryValue ?? .other }
        return ExerciseCategory.allCases.compactMap { cat in
            guard let items = dict[cat], !items.isEmpty else { return nil }
            return (cat, items.sorted { $0.name < $1.name })
        }
    }

    private var exactMatchExists: Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return exercises.contains { $0.name.compare(q, options: .caseInsensitive) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List {
                if !query.trimmingCharacters(in: .whitespaces).isEmpty && !exactMatchExists {
                    Section {
                        Button {
                            create()
                        } label: {
                            Label("Create “\(query)”", systemImage: "plus.circle.fill")
                        }
                        .accessibilityIdentifier("picker.create")
                    }
                }
                ForEach(grouped, id: \.0) { cat, items in
                    Section(cat.displayName) {
                        ForEach(items) { ex in
                            Button {
                                onPick(ex); dismiss()
                            } label: {
                                HStack {
                                    Text(ex.name)
                                    if ex.isCustom {
                                        Text("Custom").font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .foregroundStyle(.primary)
                            .accessibilityIdentifier("picker.row.\(ex.name)")
                        }
                    }
                }
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search exercises")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("picker.cancel")
                }
            }
        }
        // Expose the search field via a stable identifier for UI tests.
        .accessibilityIdentifier("picker.search")
    }

    private func create() {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let ex = try? WorkoutRepository.findOrCreateExercise(named: name, in: context) {
            onPick(ex); dismiss()
        }
    }
}
