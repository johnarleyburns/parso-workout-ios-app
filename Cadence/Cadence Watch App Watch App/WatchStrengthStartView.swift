import SwiftUI
import CadenceCore
import CadenceFeatures

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
                    WatchCustomStrengthSetupView()
                } label: {
                    Label("Custom", systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("watchStrength.custom")
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

private struct WatchCustomStrengthSetupView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager

    @AppStorage("watch.strength.lastRepPattern") private var lastRepPattern = WatchRepPattern.fallback.id
    @AppStorage("watch.strength.lastRestSeconds") private var lastRestSeconds = 60
    @AppStorage("watch.strength.lastPartners") private var lastPartners = ""

    @State private var selectedRepPatternID = WatchRepPattern.fallback.id
    @State private var selectedRestSeconds = 60
    @State private var selectedPartners = Set<String>()
    @State private var didLoadDefaults = false

    private var selectedPattern: WatchRepPattern {
        WatchRepPattern.popular.first { $0.id == selectedRepPatternID } ?? .fallback
    }

    private var partnerOptions: [String] {
        unique(decodedPartners(from: lastPartners) + watchManager.recentPartnerNames)
    }

    var body: some View {
        List {
            Section("Rep Pattern") {
                ForEach(WatchRepPattern.popular) { pattern in
                    Button {
                        WatchHaptics.tap()
                        selectedRepPatternID = pattern.id
                    } label: {
                        HStack {
                            Text(pattern.title)
                            Spacer()
                            if selectedRepPatternID == pattern.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .accessibilityIdentifier("watchStrength.repPattern.\(pattern.id)")
                }
            }

            Section("Rest") {
                ForEach(WatchRestOptions.popular, id: \.self) { seconds in
                    Button {
                        WatchHaptics.tap()
                        selectedRestSeconds = seconds
                    } label: {
                        HStack {
                            Text("\(seconds) sec")
                            Spacer()
                            if selectedRestSeconds == seconds {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .accessibilityIdentifier("watchStrength.rest.\(seconds)")
                }
            }

            Section("Partners") {
                Button {
                    WatchHaptics.tap()
                    selectedPartners.removeAll()
                } label: {
                    HStack {
                        Text("No partner")
                        Spacer()
                        if selectedPartners.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .accessibilityIdentifier("watchStrength.partner.none")

                ForEach(partnerOptions, id: \.self) { name in
                    Button {
                        WatchHaptics.tap()
                        if selectedPartners.contains(name) {
                            selectedPartners.remove(name)
                        } else {
                            selectedPartners.insert(name)
                        }
                    } label: {
                        HStack {
                            Text(name)
                                .lineLimit(1)
                            Spacer()
                            if selectedPartners.contains(name) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .accessibilityIdentifier("watchStrength.partner.\(name)")
                }
            }

            Section {
                NavigationLink {
                    WatchStrengthView(
                        title: "Strength",
                        repLadder: selectedPattern.reps,
                        initialPartnerNames: Array(selectedPartners).sorted(),
                        restSeconds: selectedRestSeconds
                    )
                    .onAppear { saveDefaults() }
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .accessibilityIdentifier("watchStrength.customStart")
            }
        }
        .navigationTitle("Custom")
        .onAppear(perform: loadDefaultsIfNeeded)
    }

    private func loadDefaultsIfNeeded() {
        guard !didLoadDefaults else { return }
        selectedRepPatternID = WatchRepPattern.normalized(parseRepPattern(lastRepPattern)).id
        selectedRestSeconds = WatchRestOptions.normalized(lastRestSeconds)
        selectedPartners = Set(decodedPartners(from: lastPartners))
        didLoadDefaults = true
    }

    private func saveDefaults() {
        lastRepPattern = selectedPattern.id
        lastRestSeconds = selectedRestSeconds
        lastPartners = encodedPartners(Array(selectedPartners).sorted())
    }

    private func parseRepPattern(_ raw: String) -> [Int] {
        raw.split(separator: "-").compactMap { Int($0) }
    }

    private func decodedPartners(from raw: String) -> [String] {
        raw.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func encodedPartners(_ names: [String]) -> String {
        names.joined(separator: "\n")
    }

    private func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  seen.insert(trimmed.lowercased()).inserted else { continue }
            out.append(trimmed)
        }
        return out
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
