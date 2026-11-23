import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// Shared setup for Lift. This view owns only a draft; WatchStrengthView is
/// created after the explicit primary Start action. Every default shown here is
/// the value that will actually be used: the last rep scheme, partners and rest
/// (or 8-8-8, no partner, and 1 minute on a fresh install).
struct WatchStrengthPreview: View {
    let launch: WatchLiftLaunch
    var citationIDs: [String] = []
    @Environment(WatchWorkoutManager.self) private var manager
    @Query(filter: #Predicate<Person> { !$0.isMe }, sort: \Person.name) private var people: [Person]
    @AppStorage(WatchStrengthPreviewDefaults.repPatternKey) private var lastRepPattern = "8-8-8"
    @AppStorage(WatchStrengthPreviewDefaults.partnersKey) private var lastPartners = ""
    @AppStorage(WatchStrengthPreviewDefaults.restSecondsKey) private var lastRestSeconds = 60
    @AppStorage(WatchStrengthPreviewDefaults.partnersChosenKey) private var partnersChosen = false
    @State private var setup: WatchStrengthPreviewSetup
    @State private var exerciseNames: [String]
    @State private var addedPrescriptions: [String: PlannedExercisePrescription] = [:]
    @State private var appliedDefaults = false
    @State private var startedLaunch: WatchLiftLaunch?
    @State private var startedPartners: [String] = []
    @State private var startedRest: Int?

    init(launch: WatchLiftLaunch, citationIDs: [String] = []) {
        self.launch = launch
        self.citationIDs = citationIDs
        _setup = State(initialValue: WatchStrengthPreviewSetup(launch: launch))
        _exerciseNames = State(initialValue: launch.exerciseNames)
    }

    private var launchPartners: [String] {
        launch.planPayload?.strength?.performers?.filter { !$0.isOwner }.map(\.displayName) ?? []
    }

    private var displayedReps: [Int] {
        setup.repOverride ?? WatchStrengthPreviewDefaults.fallbackReps
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    repDefaults
                } label: {
                    VStack(alignment: .leading) {
                        Label("Rep default", systemImage: "list.number")
                        Text(WatchStrengthPreviewDefaults.repsText(displayedReps))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("watchStrength.repDefaults")
                .accessibilityValue(WatchStrengthPreviewDefaults.repsText(displayedReps))
                NavigationLink {
                    partnerPicker
                } label: {
                    VStack(alignment: .leading) {
                        Label("Partners", systemImage: "person.2.fill")
                        Text(WatchStrengthPreviewDefaults.partnersText(setup.normalizedPartnerNames))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("watchStrength.preview.partners")
                .accessibilityValue(WatchStrengthPreviewDefaults.partnersText(setup.normalizedPartnerNames))
                NavigationLink {
                    restPicker
                } label: {
                    VStack(alignment: .leading) {
                        Label("Rest", systemImage: "timer")
                        Text(WatchStrengthPreviewDefaults.restText(setup.restSeconds ?? WatchStrengthPreviewDefaults.fallbackRestSeconds))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("watchStrength.preview.rest")
                .accessibilityValue(WatchStrengthPreviewDefaults.restText(setup.restSeconds ?? WatchStrengthPreviewDefaults.fallbackRestSeconds))
            }
            Section {
                if exerciseNames.isEmpty {
                    Text("No exercises yet. Add one with Add exercise, or start and add during the workout.")
                        .font(.footnote)
                }
                ForEach(exerciseNames, id: \.self) { name in
                    HStack {
                        Text(name.localizedExerciseName).font(.footnote)
                        Spacer()
                        NavigationLink {
                            WatchSuggestedExerciseInfoView(name: name)
                        } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("\(name) details")
                    }
                }
                NavigationLink {
                    WatchPreviewAddExerciseView(
                        existingNames: $exerciseNames,
                        addedPrescriptions: $addedPrescriptions)
                } label: {
                    Label("Add exercise", systemImage: "plus")
                }
                .accessibilityIdentifier("watchStrength.preview.addExercise")
            } header: {
                HStack {
                    Text("Exercises")
                    Spacer()
                    if !exerciseNames.isEmpty {
                        Button("Clear") {
                            WatchHaptics.tap()
                            exerciseNames = []
                            addedPrescriptions = [:]
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("watchStrength.preview.clearExercises")
                    }
                }
                .textCase(nil)
            }
            if let why = WatchLiftWhyPresentation(rationale: launch.rationale) {
                Section {
                    NavigationLink {
                        WatchLiftWhyView(presentation: why, citationIDs: citationIDs)
                    } label: {
                        Label(LocalizedStringKey(why.title), systemImage: "questionmark.circle")
                    }
                    .accessibilityIdentifier("watchStrength.whyThisWorkout")
                }
            }
            if !citationIDs.isEmpty {
                WatchCoachLineView(line: WatchCoachLine(text: "Workout sources", citationIDs: citationIDs))
            }
            if manager.isActive {
                Text("Finish or resume your current workout first.").font(.footnote)
            }
            WatchPrimaryStartButton {
                rememberDefaults()
                startedPartners = setup.normalizedPartnerNames
                startedRest = setup.restSeconds
                startedLaunch = preparedLaunch()
            }
            .disabled(manager.isActive)
            .accessibilityIdentifier("watchStrength.preview.start")
        }
        .navigationTitle(launch.title)
        .onAppear(perform: applyStoredDefaults)
        .navigationDestination(isPresented: Binding(get: { startedLaunch != nil },
            set: { if !$0 { startedLaunch = nil } })) {
                if let started = startedLaunch {
                    WatchStrengthView(title: started.title, plannedExerciseNames: started.exerciseNames,
                        repLadder: started.repLadder, planPayload: started.planPayload,
                        initialPartnerNames: startedPartners, restSeconds: startedRest)
                }
            }
    }

    private func applyStoredDefaults() {
        guard !appliedDefaults else { return }
        appliedDefaults = true
        setup.repOverride = WatchStrengthPreviewDefaults.repPattern(stored: lastRepPattern)
        setup.restSeconds = WatchStrengthPreviewDefaults.restSeconds(stored: lastRestSeconds)
        setup.partnerNames = WatchStrengthPreviewDefaults.partnerNames(
            stored: lastPartners,
            launchPartners: launchPartners,
            previouslyChosen: partnersChosen)
    }

    private func rememberDefaults() {
        lastRepPattern = WatchStrengthPreviewDefaults.repsText(displayedReps)
        lastRestSeconds = setup.restSeconds ?? WatchStrengthPreviewDefaults.fallbackRestSeconds
        lastPartners = WatchCustomStrengthDefaults.encodedPartners(setup.normalizedPartnerNames)
        partnersChosen = true
    }

    /// Applies the review choices to the launch value and keeps the visible
    /// exercise list authoritative after Clear/Add exercise edits.
    private func preparedLaunch() -> WatchLiftLaunch {
        var prepared = setup.preparedLaunch(from: launch)
        prepared.exerciseNames = exerciseNames
        var payload = prepared.planPayload ?? WatchPlanPayload(title: prepared.title)
        var strength = payload.strength ?? .init(exerciseNames: exerciseNames)
        let existing = strength.prescriptions
        strength.exerciseNames = exerciseNames
        strength.prescriptions = exerciseNames.map { name in
            addedPrescriptions[name]
                ?? existing.first { $0.exerciseName.caseInsensitiveCompare(name) == .orderedSame }
                ?? PlannedExercisePrescription(
                    exerciseName: name,
                    sets: prepared.repLadder.map { PlannedSetPrescription(targetReps: $0) })
        }
        payload.strength = strength
        prepared.planPayload = payload
        return prepared
    }

    private var repDefaults: some View {
        WatchPreviewRepPicker(reps: Binding(
            get: { setup.repOverride ?? WatchStrengthPreviewDefaults.fallbackReps },
            set: { setup.repOverride = $0 }))
    }

    private var partnerPicker: some View {
        WatchPreviewPartnerPicker(setup: $setup, recentNames: people.map(\.name))
    }

    private var restPicker: some View {
        WatchPreviewRestPicker(seconds: Binding(
            get: { setup.restSeconds ?? WatchStrengthPreviewDefaults.fallbackRestSeconds },
            set: { setup.restSeconds = $0 }))
    }
}

struct WatchPrimaryStartButton: View {
    var title: LocalizedStringKey = "Start"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "play.fill").frame(maxWidth: .infinity)
        }
        .buttonStyle(WatchPillStyle(kind: .primary))
        .accessibilityIdentifier("watchStrength.primaryStart")
    }
}

private struct WatchPreviewRepPicker: View {
    @Binding var reps: [Int]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
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
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Button("No partner") { setup.partnerNames = []; dismiss() }
                .accessibilityIdentifier("watchStrength.partner.none")
            ForEach(setup.partnerOptions(recentNames: recentNames), id: \.self) { name in
                Button { setup.togglePartner(name); dismiss() } label: {
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
                    dismiss()
                }
                .accessibilityIdentifier("watchStrength.preview.addPartner")
        }
        .navigationTitle("Partners")
    }
}

private struct WatchPreviewRestPicker: View {
    @Binding var seconds: Int
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            ForEach([30, 60, 90, 120, 180], id: \.self) { value in
                Button(WatchStrengthPreviewDefaults.restText(value)) { seconds = value; dismiss() }
                    .accessibilityIdentifier("watchStrength.rest.\(value)")
            }
        }
        .navigationTitle("Rest")
    }
}

/// Pre-start Add Exercise. It uses the same search-first picker as the live
/// workout and appends to the preview list only when the user taps a result.
struct WatchPreviewAddExerciseView: View {
    @Binding var existingNames: [String]
    @Binding var addedPrescriptions: [String: PlannedExercisePrescription]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WatchAddExercisePicker(
            existingNames: existingNames,
            activeWorkingSets: [],
            onAddCatalog: { entry in
                add(name: entry.name)
            },
            onAddSuggested: { exercise, entry in
                let result = add(name: entry.name)
                if case .added = result {
                    addedPrescriptions[entry.name] = PlannedExercisePrescription(
                        exerciseName: entry.name,
                        sets: (0..<max(1, exercise.plannedSets)).map { _ in
                            PlannedSetPrescription(targetReps: exercise.repRange.lowerBound)
                        })
                }
                return result
            },
            onCreateCustom: { name, _ in
                add(name: name)
            },
            onBack: { dismiss() },
            onAdded: { dismiss() })
    }

    private func add(name: String) -> WatchExerciseAddResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unavailable(name: trimmed) }
        guard !existingNames.contains(where: {
            $0.caseInsensitiveCompare(trimmed) == .orderedSame
        }) else { return .alreadyPresent(name: trimmed) }
        existingNames.append(trimmed)
        return .added(name: trimmed)
    }
}
