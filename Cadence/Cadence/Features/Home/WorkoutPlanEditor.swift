import SwiftUI
import SwiftData
import CadenceCore

struct EditablePlan: Hashable {
    let id = UUID()
    var title: String = "Workout"
    var warmupMinutes: Int
    var cooldownMinutes: Int
    var exercises: [EditableExercise]
    var partnerIDs: [UUID] = []

    static func empty(warmup: Int, cooldown: Int) -> EditablePlan {
        EditablePlan(warmupMinutes: warmup, cooldownMinutes: cooldown, exercises: [])
    }

    static func from(session: WorkoutSession) -> EditablePlan {
        let exercises = session.exercisesInOrder.map { ex -> EditableExercise in
            let sets = session.orderedSets.filter { $0.exercise?.id == ex.id && $0.isOwnerSet }
            return EditableExercise(
                name: ex.name,
                sets: sets.map { EditableSet(targetReps: $0.reps, targetWeight: $0.weight > 0 ? $0.weight : nil) },
                notes: ""
            )
        }
        return EditablePlan(
            title: session.title,
            warmupMinutes: 0,
            cooldownMinutes: 0,
            exercises: exercises,
            partnerIDs: session.activePartnerIDs.compactMap(UUID.init(uuidString:))
        )
    }

    static func from(plan: WorkoutPlan, ladder: [Int]?, unit: MeasurementUnitPreference,
                     warmupMinutes: Int = 0, cooldownMinutes: Int = 0) -> EditablePlan {
        let reps = ladder ?? []
        let exercises = plan.items.map { item -> EditableExercise in
            let setsCount = max(item.targetSets ?? reps.count, reps.isEmpty ? 3 : reps.count)
            let sets = (0..<setsCount).map { i -> EditableSet in
                let r = i < reps.count ? reps[i] : (item.reps ?? 5)
                return EditableSet(targetReps: r, targetWeight: nil)
            }
            return EditableExercise(name: item.movement, sets: sets, notes: item.note ?? "")
        }
        return EditablePlan(
            title: plan.name,
            warmupMinutes: warmupMinutes,
            cooldownMinutes: cooldownMinutes,
            exercises: exercises
        )
    }

    static func from(recommendation: Recommendation,
                     goal: TrainingGoal = .hypertrophy,
                     warmupMinutes: Int = 0, cooldownMinutes: Int = 0) -> EditablePlan {
        let prescribed = recommendation.prescribedSession(goal: goal)
        let ladder = prescribed.repLadder
        let names = prescribed.exerciseNames
        let exercises = names.map { name -> EditableExercise in
            let sets = ladder.isEmpty
                ? [EditableSet(targetReps: 5, targetWeight: prescribed.loadKg)]
                : ladder.map { EditableSet(targetReps: $0, targetWeight: prescribed.loadKg) }
            return EditableExercise(name: name, sets: sets, notes: "")
        }
        return EditablePlan(
            title: prescribed.title,
            warmupMinutes: warmupMinutes,
            cooldownMinutes: cooldownMinutes,
            exercises: exercises
        )
    }

    static func from(coach session: CoachSession) -> EditablePlan? {
        guard let exercises = session.exercises, !exercises.isEmpty else { return nil }
        return EditablePlan(
            title: session.title,
            warmupMinutes: 5,
            cooldownMinutes: 0,
            exercises: exercises.map { ex in
                let setCount = ex.sets ?? 3
                let ladder = ex.repLadder ?? []
                return EditableExercise(
                    name: ex.name,
                    sets: (0..<setCount).map { i in
                        EditableSet(
                            targetReps: i < ladder.count ? ladder[i] : (ex.repsLow ?? 8),
                            targetWeight: ex.loadKg
                        )
                    },
                    notes: ex.rir.map { "Target ≤\($0) RIR" } ?? ""
                )
            },
            partnerIDs: []
        )
    }
}

struct EditableExercise: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var sets: [EditableSet]
    var notes: String
}

struct EditableSet: Identifiable, Hashable {
    let id = UUID()
    var targetReps: Int
    var targetWeight: Double?
}

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

    init(plan: EditablePlan, onStart: @escaping (EditablePlan) -> Void) {
        self._plan = State(initialValue: plan)
        self.onStart = onStart

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
            List {
                Section {
                    Stepper("Warm-up: \(plan.warmupMinutes) min", value: $plan.warmupMinutes, in: 0...30)
                        .accessibilityIdentifier("editor.warmup")
                }

                Section {
                    Stepper("Get-ready countdown: \(preWorkoutCountdown)s",
                            value: $preWorkoutCountdown, in: 0...60, step: 5)
                        .accessibilityIdentifier("editor.countdown")
                }

                Section {
                    Stepper("Rest timer: \(restSeconds)s",
                            value: $restSeconds, in: 15...600, step: 15)
                        .accessibilityIdentifier("editor.restSeconds")
                    Toggle("Auto-start rest timer", isOn: $autoStartRest)
                        .accessibilityIdentifier("editor.autoRest")
                }

                Section {
                    Toggle("Round weights to nearest plate", isOn: $plateRounding)
                        .accessibilityIdentifier("editor.plateRounding")
                }

                Section {
                    Toggle("Auto-end when idle", isOn: $autoEndOnIdle)
                        .accessibilityIdentifier("editor.autoEndOnIdle")
                    Stepper("Auto-end after \(idleTimeoutMinutes) min idle",
                            value: $idleTimeoutMinutes, in: 2...30)
                        .disabled(!autoEndOnIdle)
                        .accessibilityIdentifier("editor.idleTimeout")
                } header: {
                    Text("Idle Auto-End")
                }

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
                                Button {
                                    moveRosterMember(from: index, by: -1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .disabled(index == 0)
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("editor.partnerOrder.up.\(person.isMe ? "Me" : person.name)")
                                .accessibilityLabel("Move \(person.isMe ? "Me" : person.name) earlier")

                                Button {
                                    moveRosterMember(from: index, by: 1)
                                } label: {
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

                ForEach($plan.exercises) { $exercise in
                    exerciseSection($exercise)
                }
                .onMove { plan.exercises.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { plan.exercises.remove(atOffsets: $0) }

                Section {
                    Button {
                        exercisePickerIntent = .add
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("editor.addExercise")
                }

                Section {
                    Stepper("Cool-down: \(plan.cooldownMinutes) min", value: $plan.cooldownMinutes, in: 0...30)
                        .accessibilityIdentifier("editor.cooldown")
                }

                Section {
                    Toggle("Use HR monitoring", isOn: $useHR)
                        .accessibilityIdentifier("editor.hrToggle")
                }
            }
            .environment(\.editMode, .constant(.active))
            .onAppear {
                loadSettings()
                _ = try? WorkoutRepository.me(in: modelContext)
            }

            Button(action: { saveAndStart() }) {
                Label("Start", systemImage: "play.fill")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .cadenceGlassButton(prominent: true, tint: .green)
            .padding()
            .accessibilityIdentifier("editor.start")
        }
        .navigationTitle("Workout Plan")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exercisePickerIntent) { intent in
            NavigationStack {
                ExercisePickerView(action: intent.pickerAction) { exercise in
                    applyPickedExercise(exercise, for: intent)
                    exercisePickerIntent = nil
                }
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
        let ownerID = owner?.id
        var seen = Set<UUID>()
        let cleaned = ids.filter { seen.insert($0).inserted }
        return cleaned.contains(where: { $0 != ownerID }) ? cleaned : []
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
