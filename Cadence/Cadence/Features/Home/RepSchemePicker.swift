import SwiftUI
import CadenceCore
import CadenceFeatures

struct RepSchemePicker: View {
    let plan: WorkoutPlan
    let onEditorStart: (EditablePlan) -> Void

    @Environment(AppSettings.self) private var settings

    private let presets = RepSchemePreset.all

    var body: some View {
        List {
            Section {
                ForEach(presets) { preset in
                    NavigationLink {
                        WorkoutPlanEditor(
                            plan: .from(plan: plan, ladder: preset.ladder, unit: settings.unit,
                                       warmupMinutes: settings.warmupMinutes,
                                       cooldownMinutes: settings.cooldownMinutes),
                            onStart: onEditorStart)
                    } label: {
                        Label(preset.title, systemImage: "list.number")
                    }
                    .accessibilityIdentifier(preset.accessibilityID)
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
                        plan: .from(plan: plan, ladder: reps, unit: settings.unit,
                                   warmupMinutes: settings.warmupMinutes,
                                   cooldownMinutes: settings.cooldownMinutes),
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
