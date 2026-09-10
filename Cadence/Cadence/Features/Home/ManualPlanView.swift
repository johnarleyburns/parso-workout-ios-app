import SwiftUI
import SwiftData
import CadenceCore

/// Compact athlete-facing weekly planner. It intentionally owns a unified
/// value graph rather than adapting the legacy workout-plan presets into a
/// second persistence model.
struct ManualPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var plan: Plan
    let onStart: (Session) -> Void

    @State private var sessionRoute: SessionRoute?
    @State private var didSave = false

    init(plan: Plan, onStart: @escaping (Session) -> Void) {
        self._plan = State(initialValue: plan)
        self.onStart = onStart
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Plan name", text: $plan.title)
                        .accessibilityIdentifier("manualPlan.title")
                } header: {
                    Text("Plan")
                } footer: {
                    Text("Self-authored plans stay editable and sync through your private iCloud.")
                }

                Section("This week") {
                    ForEach(ManualPlanBuilder.mondayFirst, id: \.self) { weekday in
                        dayRow(weekday)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Build your week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        savePlan()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { savePlan() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("manualPlan.save")
                }
            }
            .sheet(item: $sessionRoute) { route in
                ManualSessionEditorView(
                    session: route.session,
                    onSave: { edited in
                        replace(edited)
                        sessionRoute = nil
                        savePlan()
                    },
                    onStart: { edited in
                        replace(edited)
                        savePlan()
                        sessionRoute = nil
                        onStart(edited)
                    })
            }
        }
    }

    @ViewBuilder
    private func dayRow(_ weekday: Weekday) -> some View {
        let sessions = plan.weeks.first?.days.first(where: { $0.weekday == weekday })?.sessions ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(weekday.displayName).font(.headline)
                Spacer()
                Button {
                    addSession(to: weekday)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add session on \(weekday.displayName)")
                .accessibilityIdentifier("manualPlan.addSession.\(weekday.rawValue)")
                .disabled(sessions.count >= 2)
            }

            if sessions.isEmpty {
                Text("Rest")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions) { session in
                    Button { sessionRoute = SessionRoute(session: session) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: session.orderedItems.isEmpty ? "square.and.pencil" : "dumbbell.fill")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.title)
                                    .foregroundStyle(.primary)
                                Text(sessionSummary(session))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("manualPlan.session.\(session.id.uuidString)")
                    .swipeActions {
                        Button(role: .destructive) { remove(session) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func sessionSummary(_ session: Session) -> String {
        let strength = session.orderedItems.compactMap { item -> StrengthItem? in
            guard case let .strength(value) = item else { return nil }
            return value
        }
        let sets = strength.reduce(0) { $0 + $1.sets.count }
        if strength.isEmpty { return "No items yet" }
        return "\(strength.count) exercise\(strength.count == 1 ? "" : "s") · \(sets) sets"
    }

    private func addSession(to weekday: Weekday) {
        var updated = plan
        let session = ManualPlanBuilder.strengthSession()
        guard (try? ManualPlanBuilder.addSession(session, to: weekday, in: &updated)) != nil else { return }
        plan = updated
        sessionRoute = SessionRoute(session: session)
    }

    private func replace(_ session: Session) {
        var updated = plan
        guard (try? ManualPlanBuilder.replaceSession(session, in: &updated)) != nil else { return }
        plan = updated
    }

    private func remove(_ session: Session) {
        var updated = plan
        guard (try? ManualPlanBuilder.removeSession(id: session.id, from: &updated)) != nil else { return }
        plan = updated
        savePlan()
    }

    private func savePlan() {
        guard !plan.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        plan.authoredOnIdiom = .compact
        plan.status = .active
        plan.updatedAt = Date()
        _ = try? UnifiedPlanStore.upsert(plan, originDevice: "iphone", in: context)
        _ = try? NormalizedPlanStore.upsert(plan, originDevice: "iphone", in: context)
        didSave = true
    }
}

private struct SessionRoute: Identifiable {
    let session: Session
    var id: UUID { session.id }
}

private struct ManualSessionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session: Session
    let onSave: (Session) -> Void
    let onStart: (Session) -> Void
    @State private var itemRoute: ItemRoute?

    init(session: Session, onSave: @escaping (Session) -> Void,
         onStart: @escaping (Session) -> Void) {
        self._session = State(initialValue: session)
        self.onSave = onSave
        self.onStart = onStart
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    TextField("Session name", text: $session.title)
                        .accessibilityIdentifier("manualSession.title")
                }

                Section("Items") {
                    if session.orderedItems.isEmpty {
                        Text("Add items to build this session.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.orderedItems, id: \.id) { item in
                        Button { itemRoute = ItemRoute(item: item) } label: {
                            HStack {
                                Image(systemName: itemIcon(item)).foregroundStyle(.tint)
                                Text(itemTitle(item))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.compactMap { index in
                            session.orderedItems.indices.contains(index) ? session.orderedItems[index].id : nil
                        }
                        session.items.removeAll { ids.contains($0.id) }
                    }
                    Button { addStrengthItem() } label: {
                        Label("Add strength", systemImage: "dumbbell.fill")
                    }
                    .accessibilityIdentifier("manualSession.addStrength")
                    Button { addCardioItem() } label: {
                        Label("Add cardio", systemImage: "figure.run")
                    }
                    .accessibilityIdentifier("manualSession.addCardio")
                    Button { addMobilityItem() } label: {
                        Label("Add mobility", systemImage: "figure.flexibility")
                    }
                    .accessibilityIdentifier("manualSession.addMobility")
                    Button { addInstructionItem() } label: {
                        Label("Add instruction", systemImage: "text.alignleft")
                    }
                    .accessibilityIdentifier("manualSession.addInstruction")
                }

                Section {
                    Button {
                        onStart(session)
                    } label: {
                        Label("Start this session", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!canStart)
                    .accessibilityIdentifier("manualSession.start")
                } footer: {
                    Text(canStart
                         ? "Starting now opens the existing strength runner."
                         : "Mixed sessions are saved in the plan. Start is available once this session contains strength items only.")
                }
            }
            .navigationTitle("Edit session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(session)
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("manualSession.done")
                }
            }
            .sheet(item: $itemRoute) { route in
                switch route.item {
                case let .strength(item):
                    ManualStrengthItemEditor(item: item) { edited in
                        replace(edited)
                        itemRoute = nil
                    }
                case let .cardio(item):
                    ManualCardioItemEditor(item: item) { edited in
                        replace(edited)
                        itemRoute = nil
                    }
                case let .mobility(item):
                    ManualMobilityItemEditor(item: item) { edited in
                        replace(edited)
                        itemRoute = nil
                    }
                case let .instruction(item):
                    ManualInstructionItemEditor(item: item) { edited in
                        replace(edited)
                        itemRoute = nil
                    }
                }
            }
        }
    }

    private var canStart: Bool {
        !session.items.isEmpty && session.items.allSatisfy {
            if case .strength = $0 { return true }
            return false
        }
    }

    private func itemIcon(_ item: WorkoutItem) -> String {
        switch item {
        case .strength: return "dumbbell.fill"
        case .cardio: return "figure.run"
        case .mobility: return "figure.flexibility"
        case .instruction: return "text.alignleft"
        }
    }

    private func itemTitle(_ item: WorkoutItem) -> String {
        switch item {
        case let .strength(value):
            return value.exerciseKey.raw.replacingOccurrences(of: "_", with: " ").capitalized
        case let .cardio(value):
            switch value.prescription {
            case let .steadyState(details): return cardioActivityName(details.activity)
            case let .intervals(details): return "\(cardioActivityName(details.activity)) intervals"
            case let .open(details): return cardioActivityName(details.activity)
            }
        case let .mobility(value):
            return value.name
        case let .instruction(value):
            return value.text
        }
    }

    private func addStrengthItem() {
        let order = nextItemOrder
        let item = ManualPlanBuilder.strengthItem(exerciseKey: "back_squat", order: order)
        session.items.append(.strength(item))
        itemRoute = ItemRoute(item: .strength(item))
    }

    private func addCardioItem() {
        let item = CardioItem(
            order: nextItemOrder,
            prescription: .steadyState(SteadyState(
                activity: .run,
                durationSeconds: 20 * 60,
                intensity: .heartRateZone(2))))
        session.items.append(.cardio(item))
        itemRoute = ItemRoute(item: .cardio(item))
    }

    private func addMobilityItem() {
        let item = MobilityItem(order: nextItemOrder,
                                name: "Mobility flow",
                                rounds: 2,
                                perRound: .duration(seconds: 30))
        session.items.append(.mobility(item))
        itemRoute = ItemRoute(item: .mobility(item))
    }

    private func addInstructionItem() {
        let item = InstructionItem(order: nextItemOrder,
                                   text: "Add a note for this session.")
        session.items.append(.instruction(item))
        itemRoute = ItemRoute(item: .instruction(item))
    }

    private func replace(_ item: WorkoutItem) {
        guard let index = session.items.firstIndex(where: { $0.id == item.id }) else { return }
        session.items[index] = item
    }

    private var nextItemOrder: Int {
        (session.items.map(\.order).max() ?? -1) + 1
    }
}

private struct ItemRoute: Identifiable {
    let item: WorkoutItem
    var id: UUID { item.id }

}

private struct ManualStrengthItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @State private var item: StrengthItem
    @State private var exerciseName: String
    @State private var pickerPresented = false
    @State private var sets: [ManualSetDraft]
    let onSave: (WorkoutItem) -> Void

    init(item: StrengthItem, onSave: @escaping (WorkoutItem) -> Void) {
        self._item = State(initialValue: item)
        let name = ExerciseLibrary.starter.first {
            $0.sourceExerciseID == item.exerciseKey.raw || ExerciseLibrary.lookupKey($0.name) == item.exerciseKey.raw
        }?.name ?? item.exerciseKey.raw.replacingOccurrences(of: "_", with: " ").capitalized
        self._exerciseName = State(initialValue: name)
        self._sets = State(initialValue: item.sets.map(ManualSetDraft.init))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    Button {
                        pickerPresented = true
                    } label: {
                        HStack {
                            Text(exerciseName).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("manualStrength.chooseExercise")
                }

                Section("Sets") {
                    ForEach($sets) { $set in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Set \(set.index + 1)").font(.headline)
                                Spacer()
                                Button(role: .destructive) {
                                    sets.removeAll { $0.id == set.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                            }
                            Picker("Type", selection: $set.kind) {
                                ForEach([SetKind.warmup, .working, .backoff, .amrap, .drop], id: \.self) { kind in
                                    Text(kind.rawValue.capitalized).tag(kind)
                                }
                            }
                            TextField("Reps or AMRAP", text: $set.repsText)
                                .keyboardType(.numbersAndPunctuation)
                            Picker("Load", selection: $set.loadChoice) {
                                ForEach(LoadChoice.allCases, id: \.self) { choice in
                                    Text(choice.title).tag(choice)
                                }
                            }
                            if set.loadChoice == .absolute || set.loadChoice == .percentage {
                                TextField(set.loadChoice == .absolute ? "Weight (kg)" : "% 1RM",
                                          text: $set.loadText)
                                    .keyboardType(.decimalPad)
                            }
                            TextField("Rest seconds", text: $set.restText)
                                .keyboardType(.numberPad)
                            TextField("Target RPE (optional)", text: $set.rpeText)
                                .keyboardType(.decimalPad)
                        }
                        .padding(.vertical, 4)
                    }
                    Button {
                        sets.append(ManualSetDraft(index: sets.count))
                    } label: {
                        Label("Duplicate last set", systemImage: "plus.circle")
                    }
                    .disabled(sets.isEmpty)
                    .accessibilityIdentifier("manualStrength.duplicateSet")
                }
            }
            .navigationTitle("Strength item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("manualStrength.save")
                }
            }
            .sheet(isPresented: $pickerPresented) {
                ExercisePickerView(action: .use) { exercise in
                    exerciseName = exercise.name
                    item.exerciseKey = ExerciseKey(raw: exercise.sourceExerciseID ?? ExerciseLibrary.lookupKey(exercise.name))
                    pickerPresented = false
                }
            }
        }
    }

    private func save() {
        let mapped = sets.enumerated().map { index, draft in
            draft.prescribedSet(index: index)
        }
        item.sets = mapped.isEmpty ? [PrescribedSet(setIndex: 0, repTarget: .exact(8))] : mapped
        onSave(.strength(item))
    }
}

private enum LoadChoice: String, CaseIterable, Hashable {
    case unspecified, absolute, percentage, bodyweight

    var title: String {
        switch self {
        case .unspecified: return "No load"
        case .absolute: return "Weight"
        case .percentage: return "% 1RM"
        case .bodyweight: return "Bodyweight"
        }
    }
}

private struct ManualSetDraft: Identifiable {
    let id: UUID
    var index: Int
    var kind: SetKind = .working
    var repsText: String = "8"
    var loadChoice: LoadChoice = .unspecified
    var loadText: String = ""
    var restText: String = "90"
    var rpeText: String = ""

    init(id: UUID = UUID(), index: Int = 0) {
        self.id = id
        self.index = index
    }

    init(set: PrescribedSet) {
        self.id = set.id
        self.index = set.setIndex
        self.kind = set.kind
        switch set.repTarget {
        case let .exact(reps): self.repsText = String(reps)
        case let .range(min, max): self.repsText = "\(min)-\(max)"
        case let .amrap(minimum): self.repsText = minimum.map { "AMRAP \($0)" } ?? "AMRAP"
        case let .duration(seconds): self.repsText = String(seconds)
        case let .distance(meters): self.repsText = String(meters)
        }
        switch set.load {
        case let .absoluteWeight(value, _): self.loadChoice = .absolute; self.loadText = String(value)
        case let .percent1RM(percent, _): self.loadChoice = .percentage; self.loadText = String(percent * 100)
        case .bodyweight: self.loadChoice = .bodyweight
        default: self.loadChoice = .unspecified
        }
        self.restText = set.restSeconds.map(String.init) ?? "90"
        self.rpeText = set.targetRPE.map { String($0) } ?? ""
    }

    func prescribedSet(index: Int) -> PrescribedSet {
        let repTarget: RepTarget = {
            let normalized = repsText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if normalized.hasPrefix("AMRAP") {
                let minimum = normalized.split(separator: " ").dropFirst().first.flatMap { Int($0) }
                return .amrap(minimum: minimum)
            }
            let parts = normalized.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 2 { return .range(min: max(1, parts[0]), max: max(parts[0], parts[1])) }
            return .exact(max(1, Int(normalized) ?? 8))
        }()
        let load: LoadPrescription
        switch loadChoice {
        case .unspecified: load = .unspecified
        case .absolute: load = .absoluteWeight(value: max(0, Double(loadText) ?? 0), unit: .kg)
        case .percentage: load = .percent1RM(percent: max(0, Double(loadText) ?? 0) / 100, calculatedWeight: nil)
        case .bodyweight: load = .bodyweight
        }
        return PrescribedSet(id: id, setIndex: index, kind: kind,
                             repTarget: repTarget, load: load,
                             targetRPE: Double(rpeText),
                             restSeconds: Int(restText))
    }
}

// MARK: - Cardio item editor

private enum ManualCardioKind: String, CaseIterable, Identifiable {
    case steadyState = "Steady state"
    case intervals = "Intervals"
    case open = "Open activity"

    var id: String { rawValue }
}

private enum ManualCardioActivity: String, CaseIterable, Identifiable {
    case walk = "Walk"
    case run = "Run"
    case bike = "Bike"
    case row = "Row"
    case swim = "Swim"
    case elliptical = "Elliptical"
    case stairs = "Stairs"
    case other = "Other"

    var id: String { rawValue }

    init(activity: CardioActivity) {
        switch activity {
        case .walk: self = .walk
        case .run: self = .run
        case .bike: self = .bike
        case .row: self = .row
        case .swim: self = .swim
        case .elliptical: self = .elliptical
        case .stairs: self = .stairs
        case .other: self = .other
        }
    }

    func value(otherName: String) -> CardioActivity {
        switch self {
        case .walk: return .walk
        case .run: return .run
        case .bike: return .bike
        case .row: return .row
        case .swim: return .swim
        case .elliptical: return .elliptical
        case .stairs: return .stairs
        case .other: return .other(otherName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                   ? "Other"
                                   : otherName.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

private enum ManualIntensityMode: String, CaseIterable, Identifiable {
    case heartRateZone = "Heart-rate zone"
    case rpe = "RPE"
    case talkTest = "Talk test"

    var id: String { rawValue }
}

private struct ManualCardioItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var item: CardioItem
    @State private var kind: ManualCardioKind
    @State private var activity: ManualCardioActivity
    @State private var otherActivity: String
    @State private var instructions: String

    @State private var durationText: String
    @State private var distanceText: String
    @State private var intensityMode: ManualIntensityMode
    @State private var intensityText: String
    @State private var targetZoneEnabled: Bool

    @State private var roundsText: String
    @State private var workSecondsText: String
    @State private var recoverySecondsText: String
    @State private var recoveryMode: ManualIntensityMode
    @State private var recoveryIntensityText: String
    @State private var goalText: String

    let onSave: (WorkoutItem) -> Void

    init(item: CardioItem, onSave: @escaping (WorkoutItem) -> Void) {
        self._item = State(initialValue: item)
        self.onSave = onSave

        var initialKind = ManualCardioKind.steadyState
        var initialActivity = CardioActivity.run
        var initialDuration = ""
        var initialDistance = ""
        var initialMode = ManualIntensityMode.heartRateZone
        var initialIntensity = "2"
        var initialTargetEnabled = false
        var initialRounds = "4"
        var initialWorkSeconds = "60"
        var initialRecoverySeconds = "120"
        var initialRecoveryMode = ManualIntensityMode.heartRateZone
        var initialRecoveryIntensity = "1"
        var initialGoal = ""

        switch item.prescription {
        case let .steadyState(value):
            initialKind = .steadyState
            initialActivity = value.activity
            initialDuration = value.durationSeconds.map { String(max(1, $0 / 60)) } ?? ""
            initialDistance = value.distanceMeters.map { String($0) } ?? ""
            initialMode = manualIntensityMode(for: value.intensity)
            initialIntensity = manualIntensityValue(for: value.intensity)
            initialTargetEnabled = value.intensity != nil
        case let .intervals(value):
            initialKind = .intervals
            initialActivity = value.activity
            initialMode = manualIntensityMode(for: value.work.intensity)
            initialIntensity = manualIntensityValue(for: value.work.intensity)
            initialTargetEnabled = true
            initialRounds = String(value.rounds)
            initialWorkSeconds = value.work.durationSeconds.map { String($0) } ?? "60"
            initialRecoverySeconds = value.recovery.durationSeconds.map { String($0) } ?? "120"
            initialRecoveryMode = manualIntensityMode(for: value.recovery.intensity)
            initialRecoveryIntensity = manualIntensityValue(for: value.recovery.intensity)
        case let .open(value):
            initialKind = .open
            initialActivity = value.activity
            initialMode = manualIntensityMode(for: value.targetIntensity)
            initialIntensity = manualIntensityValue(for: value.targetIntensity)
            initialTargetEnabled = value.targetIntensity != nil
            initialGoal = value.goalText
        }

        self._kind = State(initialValue: initialKind)
        self._activity = State(initialValue: ManualCardioActivity(activity: initialActivity))
        if case let .other(name) = initialActivity {
            self._otherActivity = State(initialValue: name)
        } else {
            self._otherActivity = State(initialValue: "")
        }
        self._durationText = State(initialValue: initialDuration)
        self._distanceText = State(initialValue: initialDistance)
        self._intensityMode = State(initialValue: initialMode)
        self._intensityText = State(initialValue: initialIntensity)
        self._targetZoneEnabled = State(initialValue: initialTargetEnabled)
        self._roundsText = State(initialValue: initialRounds)
        self._workSecondsText = State(initialValue: initialWorkSeconds)
        self._recoverySecondsText = State(initialValue: initialRecoverySeconds)
        self._recoveryMode = State(initialValue: initialRecoveryMode)
        self._recoveryIntensityText = State(initialValue: initialRecoveryIntensity)
        self._goalText = State(initialValue: initialGoal)
        self._instructions = State(initialValue: item.instructions ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Cardio") {
                    Picker("Format", selection: $kind) {
                        ForEach(ManualCardioKind.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    Picker("Activity", selection: $activity) {
                        ForEach(ManualCardioActivity.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    if activity == .other {
                        TextField("Activity name", text: $otherActivity)
                    }
                }

                switch kind {
                case .steadyState:
                    steadyStateFields
                case .intervals:
                    intervalFields
                case .open:
                    openFields
                }

                Section("Instructions") {
                    TextField("Optional coaching cue", text: $instructions,
                              axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Cardio item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("manualCardio.save")
                }
            }
        }
    }

    private var steadyStateFields: some View {
        Section("Steady state") {
            TextField("Duration (minutes)", text: $durationText)
                .keyboardType(.numberPad)
            TextField("Distance (meters, optional)", text: $distanceText)
                .keyboardType(.decimalPad)
            Toggle("Set a target intensity", isOn: $targetZoneEnabled)
            if targetZoneEnabled {
                intensityFields(mode: $intensityMode, value: $intensityText)
            }
        }
    }

    private var intervalFields: some View {
        Section("Intervals") {
            TextField("Rounds", text: $roundsText)
                .keyboardType(.numberPad)
            TextField("Work seconds", text: $workSecondsText)
                .keyboardType(.numberPad)
            intensityFields(mode: $intensityMode, value: $intensityText,
                            title: "Work intensity")
            TextField("Recovery seconds", text: $recoverySecondsText)
                .keyboardType(.numberPad)
            intensityFields(mode: $recoveryMode, value: $recoveryIntensityText,
                            title: "Recovery intensity")
        }
    }

    private var openFields: some View {
        Section("Open activity") {
            TextField("Goal", text: $goalText, axis: .vertical)
                .lineLimit(2...4)
            Toggle("Set a target intensity", isOn: $targetZoneEnabled)
            if targetZoneEnabled {
                intensityFields(mode: $intensityMode, value: $intensityText)
            }
        }
    }

    @ViewBuilder
    private func intensityFields(mode: Binding<ManualIntensityMode>,
                                 value: Binding<String>,
                                 title: String = "Intensity") -> some View {
        Picker(title, selection: mode) {
            ForEach(ManualIntensityMode.allCases) { option in
                Text(option.rawValue).tag(option)
            }
        }
        TextField(mode.wrappedValue == .heartRateZone ? "Zone (1–5)" : "Value",
                  text: value)
            .keyboardType(.decimalPad)
    }

    private func save() {
        let selectedActivity = activity.value(otherName: otherActivity)
        let prescription: CardioPrescription
        switch kind {
        case .steadyState:
            let intensity = targetZoneEnabled
                ? makeIntensity(mode: intensityMode, text: intensityText)
                : nil
            prescription = .steadyState(SteadyState(
                activity: selectedActivity,
                durationSeconds: minutes(durationText),
                distanceMeters: positiveDouble(distanceText),
                intensity: intensity))
        case .intervals:
            let work = IntervalSegment(
                durationSeconds: positiveInt(workSecondsText) ?? 60,
                intensity: makeIntensity(mode: intensityMode, text: intensityText))
            let recovery = IntervalSegment(
                durationSeconds: positiveInt(recoverySecondsText) ?? 120,
                intensity: makeIntensity(mode: recoveryMode,
                                         text: recoveryIntensityText))
            prescription = .intervals(Intervals(
                activity: selectedActivity,
                rounds: max(1, positiveInt(roundsText) ?? 4),
                work: work,
                recovery: recovery))
        case .open:
            let target = targetZoneEnabled
                ? makeIntensity(mode: intensityMode, text: intensityText)
                : nil
            prescription = .open(OpenActivity(
                activity: selectedActivity,
                goalText: goalText.trimmingCharacters(in: .whitespacesAndNewlines),
                targetIntensity: target))
        }
        item.prescription = prescription
        item.instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        onSave(.cardio(item))
    }

    private func makeIntensity(mode: ManualIntensityMode, text: String) -> CardioIntensity {
        switch mode {
        case .heartRateZone:
            return .heartRateZone(min(5, max(1, Int(text) ?? 2)))
        case .rpe:
            let value = min(10, max(0, Double(text) ?? 5))
            return .rpe(value...value)
        case .talkTest:
            return .talkTest(.shortPhrases)
        }
    }

    private func minutes(_ text: String) -> Int? {
        guard let value = positiveInt(text) else { return nil }
        return value * 60
    }

    private func positiveInt(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
            return nil
        }
        return value
    }

    private func positiveDouble(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
            return nil
        }
        return value
    }

}

// MARK: - Mobility item editor

private enum ManualMobilityTarget: String, CaseIterable, Identifiable {
    case duration = "Seconds"
    case repetitions = "Reps"
    case distance = "Meters"

    var id: String { rawValue }
}

private struct ManualMobilityItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var item: MobilityItem
    @State private var name: String
    @State private var roundsText: String
    @State private var target: ManualMobilityTarget
    @State private var valueText: String
    @State private var eachSide: Bool
    @State private var instructions: String
    let onSave: (WorkoutItem) -> Void

    init(item: MobilityItem, onSave: @escaping (WorkoutItem) -> Void) {
        self._item = State(initialValue: item)
        self._name = State(initialValue: item.name)
        self._roundsText = State(initialValue: item.rounds.map(String.init) ?? "")
        self._eachSide = State(initialValue: item.eachSide)
        self._instructions = State(initialValue: item.instructions ?? "")
        switch item.perRound {
        case let .duration(seconds):
            self._target = State(initialValue: .duration)
            self._valueText = State(initialValue: String(seconds))
        case let .distance(meters):
            self._target = State(initialValue: .distance)
            self._valueText = State(initialValue: String(meters))
        case let .exact(reps):
            self._target = State(initialValue: .repetitions)
            self._valueText = State(initialValue: String(reps))
        case let .range(minimum, _):
            self._target = State(initialValue: .repetitions)
            self._valueText = State(initialValue: String(minimum))
        case let .amrap(minimum):
            self._target = State(initialValue: .repetitions)
            self._valueText = State(initialValue: String(minimum ?? 1))
        }
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mobility") {
                    TextField("Name", text: $name)
                    TextField("Rounds (optional)", text: $roundsText)
                        .keyboardType(.numberPad)
                    Toggle("Repeat each side", isOn: $eachSide)
                }
                Section("Dose") {
                    Picker("Per round", selection: $target) {
                        ForEach(ManualMobilityTarget.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    TextField("Amount", text: $valueText)
                        .keyboardType(.decimalPad)
                }
                Section("Instructions") {
                    TextField("Optional coaching cue", text: $instructions,
                              axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Mobility item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("manualMobility.save")
                }
            }
        }
    }

    private func save() {
        let amount = max(1, Double(valueText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 30)
        let perRound: RepTarget
        switch target {
        case .duration: perRound = .duration(seconds: Int(amount.rounded()))
        case .repetitions: perRound = .exact(Int(amount.rounded()))
        case .distance: perRound = .distance(meters: amount)
        }
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.rounds = Int(roundsText.trimmingCharacters(in: .whitespacesAndNewlines))
        item.perRound = perRound
        item.eachSide = eachSide
        item.instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        onSave(.mobility(item))
    }
}

// MARK: - Instruction item editor

private struct ManualInstructionItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var item: InstructionItem
    let onSave: (WorkoutItem) -> Void

    init(item: InstructionItem, onSave: @escaping (WorkoutItem) -> Void) {
        self._item = State(initialValue: item)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Instruction") {
                    TextEditor(text: $item.text)
                        .frame(minHeight: 140)
                        .accessibilityIdentifier("manualInstruction.text")
                }
                Section {
                    Text("Instructions are saved in the plan and shown as a cue when the session is reviewed or handed to a compatible execution surface.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Instruction item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        item.text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !item.text.isEmpty { onSave(.instruction(item)) }
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("manualInstruction.save")
                }
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private func manualIntensityText(for intensity: CardioIntensity?) -> String {
    switch intensity {
    case let .heartRateZone(zone): return String(zone)
    case let .rpe(range): return String(range.lowerBound)
    default: return ""
    }
}

private func manualIntensityMode(for intensity: CardioIntensity?) -> ManualIntensityMode {
    switch intensity {
    case .talkTest: return .talkTest
    case .rpe: return .rpe
    default: return .heartRateZone
    }
}

private func manualIntensityValue(for intensity: CardioIntensity?) -> String {
    manualIntensityText(for: intensity)
}

private func cardioActivityName(_ activity: CardioActivity) -> String {
    switch activity {
    case .walk: return "Walk"
    case .run: return "Run"
    case .bike: return "Bike"
    case .row: return "Row"
    case .swim: return "Swim"
    case .elliptical: return "Elliptical"
    case .stairs: return "Stairs"
    case let .other(value): return value
    }
}
