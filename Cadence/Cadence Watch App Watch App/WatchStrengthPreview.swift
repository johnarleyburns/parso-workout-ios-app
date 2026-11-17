import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// Shared setup for Personalized, Previous and Custom. This view owns only a
/// draft; WatchStrengthView is created after the explicit primary Start action.
struct WatchStrengthPreview: View {
    let launch: WatchLiftLaunch
    var citationIDs: [String] = []
    @Environment(WatchWorkoutManager.self) private var manager
    @Query(filter: #Predicate<Person> { !$0.isMe }, sort: \Person.name) private var people: [Person]
    @State private var setup: WatchStrengthPreviewSetup
    @State private var startedLaunch: WatchLiftLaunch?
    @State private var startedPartners: [String] = []
    @State private var startedRest: Int?

    init(launch: WatchLiftLaunch, citationIDs: [String] = []) {
        self.launch = launch
        self.citationIDs = citationIDs
        _setup = State(initialValue: WatchStrengthPreviewSetup(launch: launch))
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    repDefaults
                } label: {
                    VStack(alignment: .leading) {
                        Label("Rep default", systemImage: "list.number")
                        Text(setup.repOverride?.map(String.init).joined(separator: "–") ?? "Workout defaults")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("watchStrength.repDefaults")
                .accessibilityValue(setup.repOverride?.map(String.init).joined(separator: "–") ?? "Workout defaults")
                NavigationLink {
                    partnerPicker
                } label: {
                    VStack(alignment: .leading) {
                        Label("Partners", systemImage: "person.2.fill")
                        Text(setup.normalizedPartnerNames.isEmpty ? "No partner" : setup.normalizedPartnerNames.joined(separator: ", "))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("watchStrength.preview.partners")
                .accessibilityValue(setup.normalizedPartnerNames.isEmpty ? "No partner" : setup.normalizedPartnerNames.joined(separator: ", "))
                NavigationLink {
                    restPicker
                } label: {
                    VStack(alignment: .leading) {
                        Label("Rest", systemImage: "timer")
                        Text(setup.restSeconds.map { "\($0) seconds" } ?? "Workout defaults")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("watchStrength.preview.rest")
                .accessibilityValue(setup.restSeconds.map { "\($0) seconds" } ?? "Workout defaults")
            }
            Section("Exercises") {
                if launch.exerciseNames.isEmpty {
                    Text("Add exercises after starting your custom workout.").font(.footnote)
                }
                ForEach(Array(launch.exerciseNames.enumerated()), id: \.offset) { _, name in
                    HStack {
                        Text(name.localizedExerciseName).font(.footnote)
                        Spacer()
                        NavigationLink {
                            WatchSuggestedExerciseInfoView(name: name)
                        } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("\(name) details")
                    }
                }
            }
            if !citationIDs.isEmpty {
                WatchCoachLineView(line: WatchCoachLine(text: "Workout sources", citationIDs: citationIDs))
            }
            if manager.isActive {
                Text("Finish or resume your current workout first.").font(.footnote)
            }
            WatchPrimaryStartButton {
                startedPartners = setup.normalizedPartnerNames
                startedRest = setup.restSeconds
                startedLaunch = setup.preparedLaunch(from: launch)
            }
            .disabled(manager.isActive)
            .accessibilityIdentifier("watchStrength.preview.start")
        }
        .navigationTitle(launch.title)
        .navigationDestination(isPresented: Binding(get: { startedLaunch != nil },
            set: { if !$0 { startedLaunch = nil } })) {
                if let started = startedLaunch {
                    WatchStrengthView(title: started.title, plannedExerciseNames: started.exerciseNames,
                        repLadder: started.repLadder, planPayload: started.planPayload,
                        initialPartnerNames: startedPartners, restSeconds: startedRest)
                }
            }
    }

    private var repDefaults: some View {
        WatchPreviewRepPicker(reps: $setup.repOverride)
    }

    private var partnerPicker: some View {
        WatchPreviewPartnerPicker(setup: $setup, recentNames: people.map(\.name))
    }

    private var restPicker: some View {
        WatchPreviewRestPicker(seconds: $setup.restSeconds)
    }
}

struct WatchPrimaryStartButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(.accentColor)
        .controlSize(.regular)
    }
}

private struct WatchPreviewRepPicker: View {
    @Binding var reps: [Int]?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Button("Workout defaults") { reps = nil; dismiss() }
            ForEach(WatchRepPattern.popular) { pattern in
                Button(pattern.title) { reps = pattern.reps; dismiss() }
                    .accessibilityIdentifier("watchStrength.repPattern.\(pattern.id)")
            }
        }
        .navigationTitle("Rep default")
    }
}

private struct WatchPreviewPartnerPicker: View {
    @Binding var setup: WatchStrengthPreviewSetup
    let recentNames: [String]
    @State private var newPartner = ""
    var body: some View {
        List {
            Button("No partner") { setup.partnerNames = [] }
                .accessibilityIdentifier("watchStrength.partner.none")
            ForEach(setup.partnerOptions(recentNames: recentNames), id: \.self) { name in
                Button { setup.togglePartner(name) } label: {
                    HStack {
                        Text(name)
                        Spacer()
                        if setup.normalizedPartnerNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .accessibilityIdentifier("watchStrength.partner.\(name)")
            }
            TextField("Add partner", text: $newPartner)
                .onSubmit {
                    setup.partnerNames = WatchCustomStrengthDefaults.unique(setup.partnerNames + [newPartner])
                    newPartner = ""
                }
                .accessibilityIdentifier("watchStrength.preview.addPartner")
        }
        .navigationTitle("Partners")
    }
}

private struct WatchPreviewRestPicker: View {
    @Binding var seconds: Int?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Button("Workout defaults") { seconds = nil; dismiss() }
            ForEach(WatchRestOptions.popular, id: \.self) { value in
                Button("\(value) seconds") { seconds = value; dismiss() }
                    .accessibilityIdentifier("watchStrength.rest.\(value)")
            }
        }
        .navigationTitle("Rest")
    }
}
