import SwiftUI
import CadenceCore

struct RepSchemePicker: View {
    let plan: WorkoutPlan
    let onEditorStart: (EditablePlan) -> Void

    @Environment(AppSettings.self) private var settings

    private let presets: [(title: String, ladder: [Int], id: String)] = [
        ("2 sets · 8-5", [8, 5], "repScheme.2x"),
        ("3 sets · 12-10-8", [12, 10, 8], "repScheme.3x"),
        ("4 sets · 12-10-8-6", [12, 10, 8, 6], "repScheme.4x"),
    ]

    var body: some View {
        List {
            Section {
                ForEach(presets, id: \.id) { preset in
                    NavigationLink {
                        WorkoutPlanEditor(
                            plan: .from(plan: plan, ladder: preset.ladder, unit: settings.unit),
                            onStart: onEditorStart)
                    } label: {
                        Label(preset.title, systemImage: "list.number")
                    }
                    .accessibilityIdentifier(preset.id)
                }
                NavigationLink {
                    CustomRepEditor(plan: plan, onEditorStart: onEditorStart)
                } label: {
                    Label("Custom…", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("repScheme.custom")
            } header: {
                Text("Choose a set & rep scheme")
            } footer: {
                Text("The scheme applies to every movement in \(plan.name).")
            }
        }
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CustomRepEditor: View {
    let plan: WorkoutPlan
    let onEditorStart: (EditablePlan) -> Void

    @Environment(AppSettings.self) private var settings
    @State private var reps: [Int] = [12, 10, 8]

    var body: some View {
        List {
            Section("Reps per set") {
                ForEach(Array(reps.enumerated()), id: \.offset) { idx, _ in
                    Stepper(value: Binding(get: { reps[idx] },
                                           set: { reps[idx] = $0 }), in: 1...100) {
                        HStack {
                            Text("Set \(idx + 1)")
                            Spacer()
                            Text("\(reps[idx])").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("customRep.\(idx)")
                }
                HStack {
                    Button {
                        reps.append(reps.last ?? 8)
                    } label: { Label("Add set", systemImage: "plus.circle") }
                        .accessibilityIdentifier("customRep.add")
                    Spacer()
                    Button(role: .destructive) {
                        if reps.count > 1 { reps.removeLast() }
                    } label: { Label("Remove", systemImage: "minus.circle") }
                        .disabled(reps.count <= 1)
                        .accessibilityIdentifier("customRep.remove")
                }
                .buttonStyle(.borderless)
            }
            Section {
                NavigationLink {
                    WorkoutPlanEditor(
                        plan: .from(plan: plan, ladder: reps, unit: settings.unit),
                        onStart: onEditorStart)
                } label: {
                    Label("Preview \(reps.count) sets", systemImage: "chevron.right")
                }
                .accessibilityIdentifier("customRep.continue")
            }
        }
        .navigationTitle("Custom")
        .navigationBarTitleDisplayMode(.inline)
    }
}
