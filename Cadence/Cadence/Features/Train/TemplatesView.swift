import SwiftUI
import SwiftData
import CadenceCore

/// Manage reusable session templates (FR-1.6).
struct TemplatesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SessionTemplate.name) private var templates: [SessionTemplate]
    @State private var editorPresented = false

    var body: some View {
        NavigationStack {
            List {
                if templates.isEmpty {
                    ContentUnavailableView("No templates",
                                           systemImage: "square.stack.3d.up",
                                           description: Text("Create a reusable day like “Push Day”."))
                }
                ForEach(templates) { t in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name).font(.headline)
                        Text(t.orderedExercises.map(\.exerciseName).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("templateRow.\(t.name)")
                    .swipeActions {
                        Button(role: .destructive) {
                            try? WorkoutRepository.deleteTemplate(t, in: context)
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle("Templates")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("New") { editorPresented = true }
                        .accessibilityIdentifier("templates.new")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $editorPresented) { TemplateEditorView() }
        }
    }
}

/// Build a template: name + ordered exercises with target sets×reps.
struct TemplateEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var items: [Draft] = []
    @State private var pickerPresented = false

    struct Draft: Identifiable { let id = UUID(); var name: String; var sets: Int; var reps: Int }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Push Day", text: $name)
                        .accessibilityIdentifier("templateEditor.name")
                }
                Section("Exercises") {
                    ForEach($items) { $item in
                        VStack(alignment: .leading) {
                            Text(item.name).font(.headline)
                            Stepper("Sets: \(item.sets)", value: $item.sets, in: 1...12)
                            Stepper("Reps: \(item.reps)", value: $item.reps, in: 1...30)
                        }
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    Button {
                        pickerPresented = true
                    } label: { Label("Add Exercise", systemImage: "plus") }
                        .accessibilityIdentifier("templateEditor.addExercise")
                }
            }
            .navigationTitle("New Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || items.isEmpty)
                        .accessibilityIdentifier("templateEditor.save")
                }
            }
            .sheet(isPresented: $pickerPresented) {
                ExercisePickerView { ex in
                    items.append(Draft(name: ex.name, sets: 3, reps: 8))
                }
            }
        }
    }

    private func save() {
        _ = try? WorkoutRepository.createTemplate(
            name: name.trimmingCharacters(in: .whitespaces),
            exercises: items.map { ($0.name, $0.sets, $0.reps) },
            in: context)
        dismiss()
    }
}
