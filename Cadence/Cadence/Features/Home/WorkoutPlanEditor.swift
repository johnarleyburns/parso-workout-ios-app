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
            exercises: exercises
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
                     warmupMinutes: Int = 0, cooldownMinutes: Int = 0) -> EditablePlan {
        let prescribed = recommendation.prescribedSession()
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
                EditableExercise(
                    name: ex.name,
                    sets: (0..<(ex.sets ?? 3)).map { _ in
                        EditableSet(
                            targetReps: ex.repsLow ?? 8,
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

struct WorkoutPlanEditor: View {
    @State var plan: EditablePlan
    let onStart: (EditablePlan) -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Person.name) private var allPeople: [Person]
    @State private var showingExercisePicker = false
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
                    ForEach(allPeople.filter { !$0.isMe }) { person in
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
                            } else {
                                plan.partnerIDs.append(person.id)
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
                                if !plan.partnerIDs.contains(p.id) { plan.partnerIDs.append(p.id) }
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

                ForEach($plan.exercises) { $exercise in
                    exerciseSection($exercise)
                }
                .onMove { plan.exercises.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { plan.exercises.remove(atOffsets: $0) }

                Section {
                    Button {
                        showingExercisePicker = true
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
            .onAppear { loadSettings() }

            Button(action: { saveAndStart() }) {
                Label("Start", systemImage: "play.fill")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            .padding()
            .accessibilityIdentifier("editor.start")
        }
        .navigationTitle("Workout Plan")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingExercisePicker) {
            NavigationStack {
                ExercisePickerView { exercise in
                    plan.exercises.append(
                        EditableExercise(name: exercise.name, sets: [EditableSet(targetReps: 10, targetWeight: nil)], notes: "")
                    )
                    showingExercisePicker = false
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
