import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

private enum ExercisePickerIntent: Identifiable {
    case add
    case swap(UUID)

    var id: String {
        switch self {
        case .add: return "add"
        case .swap(let id): return "swap.\(id.uuidString)"
        }
    }

    var pickerAction: ExercisePickerView.PickAction {
        switch self {
        case .add: return .add
        case .swap: return .swap
        }
    }
}

struct WorkoutPlanEditor: View {
    @State var plan: EditablePlan
    let onStart: (EditablePlan) -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Person.name) private var allPeople: [Person]
    @State private var exercisePickerIntent: ExercisePickerIntent?
    @State private var newPartnerName = ""

    @State private var restSeconds: Int
    @State private var autoStartRest: Bool
    @State private var preWorkoutCountdown: Int
    @State private var autoEndOnIdle: Bool
    @State private var idleTimeoutMinutes: Int
    @State private var plateRounding: Bool
    @State private var useHR: Bool
    @State private var isEditing = false
    @State private var settingsPresented = false

    init(plan: EditablePlan, startInEditMode: Bool = false, onStart: @escaping (EditablePlan) -> Void) {
        self._plan = State(initialValue: plan)
        self.onStart = onStart
        self._isEditing = State(initialValue: startInEditMode)

        let ws = WorkoutSettings.default
        self._restSeconds = State(initialValue: ws.restSeconds)
        self._autoStartRest = State(initialValue: ws.autoStartRest)
        self._preWorkoutCountdown = State(initialValue: ws.preWorkoutCountdown)
        self._autoEndOnIdle = State(initialValue: ws.autoEndOnIdle)
        self._idleTimeoutMinutes = State(initialValue: ws.idleTimeoutMinutes)
        self._plateRounding = State(initialValue: ws.plateRounding)
        self._useHR = State(initialValue: ws.useHRMonitoring)
    }
    var body: some View {
        VStack(spacing: 0) {
            startButton
            List {
                if isEditing {
                    partnerEditorSections
                } else {
                    partnerSummarySection
                }

                if isEditing {
                    ForEach($plan.exercises) { $exercise in
                        exerciseSection($exercise)
                    }
                } else {
                    ForEach(plan.exercises) { exercise in
                        CompactExerciseRow(exercise: exercise, unit: settings.unit)
                    }
                }

                if isEditing {
                    Section {
                        Button {
                            exercisePickerIntent = .add
                        } label: {
                            Label("Add Exercise", systemImage: "plus.circle.fill")
                        }
                        .accessibilityIdentifier("editor.addExercise")
                    }
                } else {
                    Section {
                        Button {
                            settingsPresented = true
                        } label: {
                            Label("Show workout settings…", systemImage: "gearshape")
                        }
                        .accessibilityIdentifier("editor.showSettings")
                    }
                }
            }
            .onAppear {
                loadSettings()
                _ = try? WorkoutRepository.me(in: modelContext)
            }
        }
        .navigationTitle("Workout Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    withAnimation { isEditing.toggle() }
                }
                .accessibilityIdentifier("editor.edit")
            }
        }
        .sheet(item: $exercisePickerIntent) { intent in
            NavigationStack {
                ExercisePickerView(action: intent.pickerAction) { exercise in
                    applyPickedExercise(exercise, for: intent)
                    exercisePickerIntent = nil
                }
            }
        }
        .sheet(isPresented: $settingsPresented) {
            WorkoutSettingsSheet(
                warmupMinutes: $plan.warmupMinutes,
                cooldownMinutes: $plan.cooldownMinutes,
                restSeconds: $restSeconds,
                autoStartRest: $autoStartRest,
                preWorkoutCountdown: $preWorkoutCountdown,
                autoEndOnIdle: $autoEndOnIdle,
                idleTimeoutMinutes: $idleTimeoutMinutes,
                plateRounding: $plateRounding,
                useHR: $useHR)
        }
    }
    private var startButton: some View {
        Button(action: { saveAndStart() }) {
            Label("Start Workout", systemImage: "play.fill")
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green).controlSize(.large)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityIdentifier("editor.start")
    }
    private var partnerSummarySection: some View {
        Section("Training partners") {
            if selectedPartnerPeople.isEmpty {
                Text("Solo workout")
                    .foregroundStyle(.secondary)
            } else {
                Text(selectedPartnerPeople.map(\.name).joined(separator: ", "))
            }
        }
    }

    @ViewBuilder
    private var partnerEditorSections: some View {
        Section {
            ForEach(partnerPeople) { person in
                HStack {
                    Text(person.name)
                    Spacer()
                    if plan.partnerIDs.contains(person.id) {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if let idx = plan.partnerIDs.firstIndex(of: person.id) {
                        plan.partnerIDs.remove(at: idx)
                        plan.partnerIDs = normalizedPartnerIDs(plan.partnerIDs)
                    } else {
                        var ids = explicitPartnerIDs()
                        ids.append(person.id)
                        plan.partnerIDs = normalizedPartnerIDs(ids)
                    }
                }
                .accessibilityIdentifier("editor.partner.\(person.name)")
            }
            HStack {
                TextField("New partner name", text: $newPartnerName)
                    .accessibilityIdentifier("editor.newPartnerName")
                Button("Add") {
                    let name = newPartnerName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty,
                       let p = try? WorkoutRepository.findOrCreatePerson(named: name, in: modelContext) {
                        if !plan.partnerIDs.contains(p.id) {
                            var ids = explicitPartnerIDs()
                            ids.append(p.id)
                            plan.partnerIDs = normalizedPartnerIDs(ids)
                        }
                    }
                    newPartnerName = ""
                }
                .disabled(newPartnerName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("editor.addPartner")
            }
        } header: {
            Text("Training partners")
        } footer: {
            Text("Partners are optional — leave everyone unchecked to train solo.")
        }
        if !selectedPartnerPeople.isEmpty {
            Section {
                ForEach(Array(editorRoster.enumerated()), id: \.element.id) { index, person in
                    HStack {
                        Text(person.isMe ? "Me" : person.name)
                        Spacer()
                        Button { moveRosterMember(from: index, by: -1) } label: {
                            Image(systemName: "chevron.up")
                        }
                        .disabled(index == 0)
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("editor.partnerOrder.up.\(person.isMe ? "Me" : person.name)")
                        .accessibilityLabel("Move \(person.isMe ? "Me" : person.name) earlier")
                        Button { moveRosterMember(from: index, by: 1) } label: {
                            Image(systemName: "chevron.down")
                        }
                        .disabled(index >= editorRoster.count - 1)
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("editor.partnerOrder.down.\(person.isMe ? "Me" : person.name)")
                        .accessibilityLabel("Move \(person.isMe ? "Me" : person.name) later")
                    }
                }
            } header: {
                Text("Performer order")
            } footer: {
                Text("The logger rotates through this order after each saved set.")
            }
        }
    }
    private func loadSettings() {
        let ws = settings.lastStrengthSettings
        restSeconds = ws.restSeconds
        autoStartRest = ws.autoStartRest
        preWorkoutCountdown = ws.preWorkoutCountdown
        autoEndOnIdle = ws.autoEndOnIdle
        idleTimeoutMinutes = ws.idleTimeoutMinutes
        plateRounding = ws.plateRounding
        useHR = ws.useHRMonitoring
    }

    private func saveAndStart() {
        let ws = WorkoutSettings(
            restSeconds: restSeconds,
            autoStartRest: autoStartRest,
            preWorkoutCountdown: preWorkoutCountdown,
            autoEndOnIdle: autoEndOnIdle,
            idleTimeoutMinutes: idleTimeoutMinutes,
            plateRounding: plateRounding,
            gpsHighAccuracy: settings.lastStrengthSettings.gpsHighAccuracy,
            autoPause: settings.lastStrengthSettings.autoPause,
            intervalColorBlind: settings.lastStrengthSettings.intervalColorBlind,
            spokenCues: settings.lastStrengthSettings.spokenCues,
            weeklyCardioMinutesGoal: settings.lastStrengthSettings.weeklyCardioMinutesGoal,
            warmupMinutes: plan.warmupMinutes,
            cooldownMinutes: plan.cooldownMinutes,
            useHRMonitoring: useHR
        )
        settings.lastStrengthSettings = ws

        settings.restSeconds = restSeconds
        settings.autoStartRest = autoStartRest
        settings.preWorkoutCountdown = preWorkoutCountdown
        settings.autoEndOnIdle = autoEndOnIdle
        settings.idleTimeoutMinutes = idleTimeoutMinutes
        settings.plateRounding = plateRounding
        settings.useHRMonitoring = useHR

        onStart(plan)
    }

    @ViewBuilder
    private func exerciseSection(_ exercise: Binding<EditableExercise>) -> some View {
        Section {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                Text(exercise.wrappedValue.name).font(.headline)
                Spacer()
                Menu {
                    Button {
                        exercisePickerIntent = .swap(exercise.wrappedValue.id)
                    } label: {
                        Label("Swap Exercise", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier("editor.swapExercise.\(exercise.wrappedValue.name)")

                    Button(role: .destructive) {
                        removeExercise(id: exercise.wrappedValue.id)
                    } label: {
                        Label("Remove Exercise", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
                .accessibilityIdentifier("editor.exerciseMenu.\(exercise.wrappedValue.name)")
                .accessibilityLabel("Exercise options")
            }
            .accessibilityIdentifier("editor.exercise.\(exercise.wrappedValue.name)")

            ForEach(exercise.sets) { $set in
                setRow($set, unit: settings.unit)
            }
            .onDelete { exercise.wrappedValue.sets.remove(atOffsets: $0) }

            Button {
                let lastReps = exercise.wrappedValue.sets.last?.targetReps ?? 10
                let lastWeight = exercise.wrappedValue.sets.last?.targetWeight
                exercise.wrappedValue.sets.append(EditableSet(targetReps: lastReps, targetWeight: lastWeight))
            } label: {
                Label("Add Set", systemImage: "plus")
                    .font(.subheadline)
            }
            .accessibilityIdentifier("editor.addSet.\(exercise.wrappedValue.name)")
        }
    }

    private var owner: Person? {
        allPeople.first(where: \.isMe)
    }

    private var partnerPeople: [Person] {
        allPeople.filter { !$0.isMe }
    }

    private var selectedPartnerPeople: [Person] {
        let ids = Set(plan.partnerIDs)
        return partnerPeople.filter { ids.contains($0.id) }
    }

    private var editorRoster: [Person] {
        guard !selectedPartnerPeople.isEmpty else { return owner.map { [$0] } ?? [] }
        let peopleByID = Dictionary(allPeople.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let selectedIDs = Set(selectedPartnerPeople.map(\.id))
        var seen = Set<UUID>()
        let ordered = plan.partnerIDs.compactMap { id -> Person? in
            guard seen.insert(id).inserted else { return nil }
            return peopleByID[id]
        }
        if ordered.contains(where: \.isMe) {
            return ordered.filter { $0.isMe || selectedIDs.contains($0.id) }
        }
        return (owner.map { [$0] } ?? []) + selectedPartnerPeople
    }

    private func explicitPartnerIDs() -> [UUID] {
        guard !selectedPartnerPeople.isEmpty else {
            return owner.map { [$0.id] } ?? []
        }
        let ids = editorRoster.map(\.id)
        return ids.isEmpty ? plan.partnerIDs : ids
    }

    private func normalizedPartnerIDs(_ ids: [UUID]) -> [UUID] {
        EditablePlan.normalizedPartnerIDs(ids, ownerID: owner?.id)
    }

    private func moveRosterMember(from index: Int, by offset: Int) {
        var ids = explicitPartnerIDs()
        let target = index + offset
        guard ids.indices.contains(index), ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
        plan.partnerIDs = normalizedPartnerIDs(ids)
    }

    private func removeExercise(id: UUID) {
        plan.exercises.removeAll { $0.id == id }
    }

    private func applyPickedExercise(_ exercise: Exercise, for intent: ExercisePickerIntent) {
        switch intent {
        case .add:
            plan.exercises.append(
                EditableExercise(name: exercise.name, sets: [EditableSet(targetReps: 10, targetWeight: nil)], notes: "")
            )
        case .swap(let id):
            guard let index = plan.exercises.firstIndex(where: { $0.id == id }) else { return }
            plan.exercises[index].name = exercise.name
        }
    }

    private func setRow(_ set: Binding<EditableSet>, unit: MeasurementUnitPreference) -> some View {
        HStack {
            Stepper("Reps: \(set.wrappedValue.targetReps)", value: set.targetReps, in: 1...100)
                .frame(maxWidth: .infinity)
            if let w = set.wrappedValue.targetWeight {
                Text(Format.weight(w, unit: unit))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
        }
    }
}
