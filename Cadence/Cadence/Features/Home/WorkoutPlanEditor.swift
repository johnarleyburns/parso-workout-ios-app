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
        ScrollView {
            VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.sectionSpacing)) {
                startButton

                WorkoutPlanPartnerSection(partnerIDs: $plan.partnerIDs,
                                          isEditing: isEditing,
                                          allPeople: allPeople,
                                          onRosterChanged: resolvePartnerPlans)

                if isEditing {
                    ForEach($plan.exercises) { $exercise in
                        WorkoutPlanExerciseSection(
                            exercise: $exercise,
                            unit: settings.unit,
                            onSwap: { exercisePickerIntent = .swap(exercise.id) },
                            onRemove: { removeExercise(id: exercise.id) })
                    }
                    addExerciseButton
                } else {
                    ForEach(plan.exercises) { exercise in
                        CompactExerciseRow(exercise: exercise, unit: settings.unit)
                            .workoutPlanCard()
                    }
                    settingsButton
                }
            }
            .padding(CGFloat(LayoutMetrics.pagePadding))
        }
        .onAppear {
            loadSettings()
            _ = try? WorkoutRepository.me(in: modelContext)
            resolvePartnerPlans()
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
        CadenceActionButton(title: "Start Workout", systemImage: "play.fill") {
            saveAndStart()
        }
        .accessibilityIdentifier("editor.start")
    }

    private var addExerciseButton: some View {
        CadenceActionButton(title: "Add Exercise",
                            systemImage: "plus.circle.fill",
                            emphasis: .secondary) {
            exercisePickerIntent = .add
        }
        .accessibilityIdentifier("editor.addExercise")
    }

    private var settingsButton: some View {
        CadenceActionButton(title: "Show workout settings\u{2026}",
                            systemImage: "gearshape",
                            emphasis: .secondary) {
            settingsPresented = true
        }
        .accessibilityIdentifier("editor.showSettings")
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

    private func removeExercise(id: UUID) {
        plan.exercises.removeAll { $0.id == id }
    }

    /// Fills every partner's plan from *their* history for the owner's
    /// exercises (field test 2026-08-18 #4). Runs on appear, on roster changes
    /// and after an exercise is added or swapped — never per keystroke.
    private func resolvePartnerPlans() {
        let roster = rosterMembers()
        guard !plan.exercises.isEmpty else { return }
        plan = PartnerPlanResolver.fill(plan: plan, roster: roster) { name, performerID in
            WorkoutPlanPartnerHistory.history(forExerciseNamed: name,
                                              performerID: performerID,
                                              people: allPeople,
                                              context: modelContext)
        }
    }

    /// The owner first, then the selected partners in the order the roster card
    /// records — the same order the logger rotates through.
    private func rosterMembers() -> [PartnerPlanResolver.RosterMember] {
        let owner = PartnerPlanResolver.RosterMember(performerID: nil, name: "Me")
        let peopleByID = Dictionary(allPeople.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let partners = plan.partnerIDs.compactMap { id -> PartnerPlanResolver.RosterMember? in
            guard let person = peopleByID[id], !person.isMe else { return nil }
            return PartnerPlanResolver.RosterMember(performerID: person.id, name: person.name)
        }
        return [owner] + partners
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
        resolvePartnerPlans()
    }
}

extension View {
    /// Home's card treatment (`cardPadding`, corner 16, glass) so the plan
    /// editor reads exactly like Home once it is no longer a `List`.
    func workoutPlanCard() -> some View {
        padding(CGFloat(LayoutMetrics.cardPadding))
            .frame(maxWidth: .infinity, alignment: .leading)
            .cadenceGlassCard(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: .green)
    }
}
