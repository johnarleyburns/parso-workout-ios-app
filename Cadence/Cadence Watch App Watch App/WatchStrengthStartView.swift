import SwiftUI
import SwiftData
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
    @Query(sort: \Person.updatedAt, order: .reverse) private var people: [Person]

    @AppStorage("watch.strength.lastRepPattern") private var lastRepPattern = WatchRepPattern.fallback.id
    @AppStorage("watch.strength.lastRestSeconds") private var lastRestSeconds = 60
    @AppStorage("watch.strength.lastPartners") private var lastPartners = ""

    @State private var selectedRepPatternID = WatchRepPattern.fallback.id
    @State private var selectedRestSeconds = 60
    @State private var selectedPartnerNames: [String] = []
    @State private var didLoadDefaults = false
    @State private var launchConfig: WatchCustomStrengthLaunchConfig?

    private var selectedPattern: WatchRepPattern {
        WatchRepPattern.popular.first { $0.id == selectedRepPatternID } ?? .fallback
    }

    private var recentLocalPartnerNames: [String] {
        people
            .filter { !$0.isMe && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(\.name)
    }

    private var partnerOptions: [String] {
        WatchCustomStrengthDefaults.unique(
            WatchCustomStrengthDefaults.decodedPartners(from: lastPartners)
                + watchManager.recentPartnerNames
                + recentLocalPartnerNames
        )
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
                    selectedPartnerNames.removeAll()
                } label: {
                    HStack {
                        Text("No partner")
                        Spacer()
                        if selectedPartnerNames.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .accessibilityIdentifier("watchStrength.partner.none")

                ForEach(partnerOptions, id: \.self) { name in
                    Button {
                        WatchHaptics.tap()
                        if let index = selectedPartnerNames.firstIndex(where: { $0.compare(name, options: .caseInsensitive) == .orderedSame }) {
                            selectedPartnerNames.remove(at: index)
                        } else {
                            selectedPartnerNames.append(name)
                        }
                    } label: {
                        HStack {
                            Text(name)
                                .lineLimit(1)
                            Spacer()
                            if selectedPartnerNames.contains(where: { $0.compare(name, options: .caseInsensitive) == .orderedSame }) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .accessibilityIdentifier("watchStrength.partner.\(name)")
                }
            }

            Section {
                Button {
                    WatchHaptics.success()
                    saveDefaults()
                    launchConfig = WatchCustomStrengthLaunchConfig(
                        repLadder: selectedPattern.reps,
                        partnerNames: WatchCustomStrengthDefaults.unique(selectedPartnerNames),
                        restSeconds: selectedRestSeconds
                    )
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("watchStrength.customStart")
            }
        }
        .navigationTitle("Custom")
        .onAppear(perform: loadDefaultsIfNeeded)
        .navigationDestination(item: $launchConfig) { config in
            WatchStrengthView(
                title: "Strength",
                repLadder: config.repLadder,
                initialPartnerNames: config.partnerNames,
                restSeconds: config.restSeconds
            )
        }
    }

    private func loadDefaultsIfNeeded() {
        guard !didLoadDefaults else { return }
        let defaults = WatchCustomStrengthDefaults(
            storedRepPattern: lastRepPattern,
            storedRestSeconds: lastRestSeconds,
            storedPartners: lastPartners,
            recentPartners: watchManager.recentPartnerNames + recentLocalPartnerNames
        )
        selectedRepPatternID = defaults.repPattern.id
        selectedRestSeconds = defaults.restSeconds
        selectedPartnerNames = defaults.selectedPartners
        didLoadDefaults = true
    }

    private func saveDefaults() {
        lastRepPattern = selectedPattern.id
        lastRestSeconds = selectedRestSeconds
        lastPartners = WatchCustomStrengthDefaults.encodedPartners(selectedPartnerNames)
    }
}

private struct WatchCustomStrengthLaunchConfig: Hashable, Identifiable {
    let id = UUID()
    let repLadder: [Int]
    let partnerNames: [String]
    let restSeconds: Int
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
