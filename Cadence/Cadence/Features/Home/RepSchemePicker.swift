import SwiftUI
import CadenceCore

/// Set & rep scheme chooser for a flexible Strength-library template (feedback
/// batch 3). The user picks one scheme and it's applied to every movement in the
/// preset (e.g. all Push exercises become 3 sets of 12-10-8). Pushed inside the
/// Start-Workout sheet's navigation (like the preset previews) so launching stays
/// the parent's job and dismisses the whole sheet at once.
struct RepSchemePicker: View {
    let plan: WorkoutPlan
    /// Launches the preset with the chosen rep ladder.
    let onStart: (WorkoutPlan, [Int]?) -> Void

    /// The built-in schemes (sets × descending reps), as the user described them.
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
                        PlanPreviewView(plan: plan, repLadder: preset.ladder) {
                            onStart(plan, preset.ladder)
                        }
                    } label: {
                        Label(preset.title, systemImage: "list.number")
                    }
                    .accessibilityIdentifier(preset.id)
                }
                NavigationLink {
                    CustomRepEditor(plan: plan, onStart: onStart)
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

/// Per-set rep entry for a custom scheme (feedback batch 3): type each set's
/// reps, then preview + start. The set count grows/shrinks with Add/Remove.
struct CustomRepEditor: View {
    let plan: WorkoutPlan
    let onStart: (WorkoutPlan, [Int]?) -> Void

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
                    PlanPreviewView(plan: plan, repLadder: reps) {
                        onStart(plan, reps)
                    }
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
