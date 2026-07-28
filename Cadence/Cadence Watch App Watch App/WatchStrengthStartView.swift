import SwiftUI
import CadenceCore

struct WatchStrengthStartView: View {
    private var presets: [WorkoutPlan] {
        let preferred = [
            "preset-push",
            "preset-pull",
            "preset-legs",
            "preset-upper",
            "preset-lower",
            "preset-dup-hypertrophy",
            "preset-dup-heavy",
            "preset-fullbody-fallback",
        ]
        let byID = Dictionary(uniqueKeysWithValues: StrengthPresets.all.map { ($0.id, $0) })
        return preferred.compactMap { byID[$0] }
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    WatchStrengthView(title: "Strength")
                } label: {
                    Label("Custom", systemImage: "plus.circle.fill")
                }
            }

            Section("Prescriptions") {
                ForEach(presets) { plan in
                    if plan.flexibleScheme {
                        NavigationLink {
                            WatchRepSchemePicker(plan: plan)
                        } label: {
                            presetLabel(plan)
                        }
                    } else {
                        NavigationLink {
                            WatchStrengthView(
                                title: plan.displayTitle,
                                plannedExerciseNames: plan.movementNames,
                                planKey: plan.id
                            )
                        } label: {
                            presetLabel(plan)
                        }
                    }
                }
            }
        }
        .navigationTitle("Strength")
    }

    private func presetLabel(_ plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(plan.name)
                .fontWeight(.semibold)
            Text(plan.movementNames.prefix(3).joined(separator: ", "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

private struct WatchRepSchemePicker: View {
    let plan: WorkoutPlan

    private let presets: [(title: String, ladder: [Int])] = [
        ("2 sets · 8-5", [8, 5]),
        ("3 sets · 12-10-8", [12, 10, 8]),
        ("4 sets · 12-10-8-6", [12, 10, 8, 6]),
    ]

    var body: some View {
        List {
            Section("Rep Scheme") {
                ForEach(presets, id: \.title) { preset in
                    NavigationLink {
                        WatchStrengthView(
                            title: plan.displayTitle,
                            plannedExerciseNames: plan.movementNames,
                            repLadder: preset.ladder,
                            planKey: plan.id
                        )
                    } label: {
                        Label(preset.title, systemImage: "list.number")
                    }
                }
            }
        }
        .navigationTitle(plan.name)
    }
}
