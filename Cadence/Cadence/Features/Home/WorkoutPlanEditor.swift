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
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @State private var exercisePickerIntent: ExercisePickerIntent?

    @State private var restSeconds: Int
    @State private var autoStartRest: Bool
    @State private var preWorkoutCountdown: Int
    @State private var autoEndOnIdle: Bool
    @State private var idleTimeoutMinutes: Int
    @State private var plateRounding: Bool
    @State private var useHR: Bool
    @State private var isEditing = false
    @State private var originalPlan: EditablePlan
    @State private var settingsPresented = false
    @State private var historyIndex: WorkoutPlanPartnerHistory.Index?
    @State private var didResolvePartnerPlans = false
    @State private var exerciseIndex: [String: Exercise] = [:]
    let allowsStart: Bool

    init(plan: EditablePlan, startInEditMode: Bool = false, allowsStart: Bool = true,
         onStart: @escaping (EditablePlan) -> Void) {
        self._plan = State(initialValue: plan)
        self.onStart = onStart
        self._isEditing = State(initialValue: startInEditMode)
        self._originalPlan = State(initialValue: plan)
        self.allowsStart = allowsStart

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
                if allowsStart { startButton }

                WorkoutPlanPartnerSection(partnerIDs: $plan.partnerIDs,
                                          isEditing: isEditing,
                                          allPeople: allPeople,
                                          onRosterChanged: resolvePartnerPlans)

                if isEditing {
                    ForEach($plan.exercises) { $exercise in
                        WorkoutPlanExerciseSection(
                            exercise: $exercise,
                            unit: settings.unit,
                            exerciseInfo: exerciseIndex[exercise.name.lowercased()] ??
                                allExercises.first { $0.name == exercise.name },
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
            if historyIndex == nil {
                let index = WorkoutPlanPartnerHistory.Index(context: modelContext)
                historyIndex = index
                exerciseIndex = Dictionary(allExercises.map { ($0.name.lowercased(), $0) },
                                           uniquingKeysWith: { first, _ in first })
            }
            if !didResolvePartnerPlans {
                resolvePartnerPlans()
                didResolvePartnerPlans = true
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
        .safeAreaInset(edge: .bottom) {
            if isEditing {
                HStack(spacing: 12) {
                    Button("Cancel") {
                        plan = originalPlan
                        withAnimation { isEditing = false }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("editor.cancel")

                    Button("Save") {
                        originalPlan = plan
                        withAnimation { isEditing = false }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("editor.save")
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .sheet(item: $exercisePickerIntent) { intent in
            NavigationStack {
                ExercisePickerView(action: intent.pickerAction, source: {
                    if case .swap(let id) = intent,
                       let name = plan.exercises.first(where: { $0.id == id })?.name {
                        return allExercises.first { $0.name == name }
                    }
                    return nil
                }()) { exercise in
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
        let index: WorkoutPlanPartnerHistory.Index
        if let historyIndex {
            index = historyIndex
        } else {
            index = WorkoutPlanPartnerHistory.Index(context: modelContext)
            historyIndex = index
        }
        plan = PartnerPlanResolver.fill(plan: plan, roster: roster) { name, performerID in
            index.history(forExerciseNamed: name, performerID: performerID, people: allPeople)
        }
    }

    /// The roster card's persisted order, including a partner-before-owner plan.
    /// Legacy drafts that do not explicitly contain the owner remain owner-first.
    private func rosterMembers() -> [PartnerPlanResolver.RosterMember] {
        let peopleByID = Dictionary(allPeople.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = plan.partnerIDs.compactMap { id -> PartnerPlanResolver.RosterMember? in
            guard let person = peopleByID[id] else { return nil }
            return PartnerPlanResolver.RosterMember(
                performerID: person.isMe ? nil : person.id,
                name: person.isMe ? "Me" : person.name)
        }
        let hasPartner = ordered.contains { $0.performerID != nil }
        guard hasPartner else {
            return [PartnerPlanResolver.RosterMember(performerID: nil, name: "Me")]
        }
        if ordered.contains(where: { $0.performerID == nil }) { return ordered }
        return [PartnerPlanResolver.RosterMember(performerID: nil, name: "Me")] + ordered
    }

    private func applyPickedExercise(_ exercise: Exercise, for intent: ExercisePickerIntent) {
        switch intent {
        case .add:
            plan.exercises.append(
                EditableExercise(name: exercise.name, sets: ownerSeedSets(for: exercise.name), notes: "")
            )
        case .swap(let id):
            guard let index = plan.exercises.firstIndex(where: { $0.id == id }) else { return }
            plan.exercises[index].name = exercise.name
        }
        resolvePartnerPlans()
    }

    /// The plan is now the prescription the live session honours (field test
    /// 2026-08-19 #1), so a newly added exercise has to open with what the user
    /// would actually be given: their own last session on that lift, or their
    /// usual reps — not a hard-coded 10 the session then quietly overrode.
    private func ownerSeedSets(for name: String) -> [EditableSet] {
        PartnerPlanResolver.ownerSeedSets(
            history: WorkoutPlanPartnerHistory.history(forExerciseNamed: name,
                                                       performerID: nil,
                                                       people: allPeople,
                                                       context: modelContext),
            defaultReps: 10)
    }
}

extension View {
    /// Home's card treatment (`cardPadding`, corner 16, glass) so the plan
    /// editor reads exactly like Home once it is no longer a `List`.
    func workoutPlanCard() -> some View {
        padding(CGFloat(LayoutMetrics.cardPadding))
            .frame(maxWidth: .infinity, alignment: .leading)
            .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .green)
    }
}
