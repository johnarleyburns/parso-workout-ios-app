import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

enum ExercisePickerIntent: Identifiable {
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
    /// Supplied only when this plan came from the suggested-workout chooser.
    /// Real report: excluding an exercise from a suggested workout left it
    /// sitting right there in the plan, because excluding only ever changed
    /// *future* suggestion runs. When set, excluding an exercise here
    /// recomputes the whole plan from scratch (not a patch) with that
    /// exercise's candidate removed, for the SAME chosen style, and replaces
    /// `plan` with the result. Every other entry point (a saved routine, a
    /// custom/manual plan) leaves this `nil`, so excluding there keeps the
    /// previous "affects future suggestions only" behavior.
    ///
    /// Takes the plain `ExerciseSuggestionExclusionKey` string rather than
    /// the SwiftData `Exercise` itself — `Exercise` is main-actor model
    /// state, not `Sendable`, and this closure crosses into a background
    /// `Task` to run the (CPU-heavy) regeneration off the main actor.
    var onExcludeAndRegenerate: ((String) async -> EditablePlan?)? = nil

    @Environment(AppSettings.self) var settings
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) private var dismiss
    // Shared with the editor's file-split extensions. Swift access control is
    // file-scoped only for `fileprivate`; `private` prevents the Xcode app
    // target from compiling these extensions even though SwiftPM exercises
    // their underlying core types.
    @Query(sort: \Person.name) var allPeople: [Person]
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]
    @State var exercisePickerIntent: ExercisePickerIntent?

    @State private var restSeconds: Int
    @State private var autoStartRest: Bool
    @State private var preWorkoutCountdown: Int
    @State private var autoEndOnIdle: Bool
    @State private var idleTimeoutMinutes: Int
    @State private var plateRounding: Bool
    @State private var useHR: Bool
    @State var isEditing = false
    @State var originalPlan: EditablePlan
    @State var settingsPresented = false
    @State var historyIndex: WorkoutPlanPartnerHistory.Index?
    @State private var didResolvePartnerPlans = false
    @State var exerciseIndex: [String: Exercise] = [:]
    @State private var exclusionExercise: Exercise?
    @State private var isRegeneratingAfterExclusion = false
    @State private var regenerationFailed = false
    @State var planVolumeState = LiveWorkoutVolumeState()
    @State var planVolumeWeekly: [MuscleGroup: Double] = [:]
    @State var planVolumePerformers: [VolumeSummaryPerformer] = []
    @State var planVolumePerformerStates: [String: LiveWorkoutVolumeState] = [:]
    @State private var planVolumeExpanded = false
    @State var suggestExerciseRequest: SuggestedExerciseRequest?
    @State var schedulePresented = false
    @State var suggestExerciseFailed = false
    let allowsStart: Bool
    let allowsSchedule: Bool

    init(plan: EditablePlan, startInEditMode: Bool = false, allowsStart: Bool = true,
         allowsSchedule: Bool = true,
         onExcludeAndRegenerate: ((String) async -> EditablePlan?)? = nil,
         onStart: @escaping (EditablePlan) -> Void) {
        self._plan = State(initialValue: plan)
        self.onStart = onStart
        self.onExcludeAndRegenerate = onExcludeAndRegenerate
        self._isEditing = State(initialValue: startInEditMode)
        self._originalPlan = State(initialValue: plan)
        self.allowsStart = allowsStart
        self.allowsSchedule = allowsSchedule

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
            LazyVStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.sectionSpacing)) {
                if allowsStart {
                    startButton
                    if allowsSchedule { scheduleButton }
                }

                LiveWorkoutVolumeSummary(state: planVolumeState,
                                         expanded: $planVolumeExpanded,
                                         presentation: .planned,
                                         accessibilityPrefix: "plan",
                                         performers: planVolumePerformers,
                                         performerStates: planVolumePerformerStates)

                WorkoutPlanPartnerSection(partnerIDs: $plan.partnerIDs,
                                          isEditing: isEditing,
                                          allPeople: allPeople,
                                          onRosterChanged: resolvePartnerPlans)

                if isEditing {
                    ForEach($plan.exercises) { $exercise in
                        WorkoutPlanExerciseSection(
                            exercise: $exercise,
                            unit: settings.unit,
                            exerciseInfo: exerciseIndex[exercise.name.lowercased()],
                            onSwap: { exercisePickerIntent = .swap(exercise.id) },
                            onRemove: { removeExercise(id: exercise.id) },
                            onExclude: { exclusionExercise = exerciseIndex[exercise.name.lowercased()] })
                    }
                    addExerciseButton
                } else {
                    ForEach(plan.exercises) { exercise in
                        CompactExerciseRow(
                            exercise: exercise,
                            unit: settings.unit,
                            exerciseInfo: exerciseIndex[exercise.name.lowercased()],
                            onExclude: { exclusionExercise = exerciseIndex[exercise.name.lowercased()] })
                            .workoutPlanCard()
                    }
                    settingsButton
                }
                suggestExerciseButton
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
            refreshPlanVolume()
            refreshPlanWeeklyVolume()
        }
        .onChange(of: plan) { _, _ in refreshPlanVolume() }
        .onChange(of: allExercises.count) { _, _ in
            exerciseIndex = Dictionary(allExercises.map { ($0.name.lowercased(), $0) },
                                       uniquingKeysWith: { first, _ in first })
            refreshPlanVolume()
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
                        return exerciseIndex[name.lowercased()]
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
        .sheet(isPresented: $schedulePresented) {
            ScheduleWorkoutSheet(title: plan.title) { date in
                try schedule(plan: plan, for: date)
            }
        }
        .sheet(item: $exclusionExercise) { exercise in
            ExerciseSuggestionExclusionSheet(exercise: exercise, onExcluded: {
                regenerateAfterExcluding(exercise)
            })
        }
        .sheet(item: $suggestExerciseRequest) { request in
            SuggestExerciseView(request: request,
                                exerciseForName: { name in
                                    exerciseIndex[name.lowercased()]
                                },
                                onAdd: addSuggestedExercise)
        }
        .overlay {
            if isRegeneratingAfterExclusion {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView("Rebuilding your suggested workout…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                .accessibilityIdentifier("editor.regenerating")
            }
        }
        .alert("Couldn't rebuild this workout", isPresented: $regenerationFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The exercise was excluded from future suggestions, but this plan could not be recalculated. You can remove it manually below.")
        }
        .alert("Couldn't suggest an exercise", isPresented: $suggestExerciseFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Exercise data could not be read. Try again after the catalog finishes loading.")
        }
    }

    private func schedule(plan: EditablePlan, for date: Date) throws {
        _ = try ScheduledWorkoutStore.schedule(plan: plan, for: date, in: modelContext)
        NotificationCenter.default.post(name: .scheduledWorkoutCreated, object: nil)
        dismiss()
    }

    /// Regenerates the whole suggested plan from scratch now that `exercise`
    /// is excluded — never a patch that just deletes the row and leaves
    /// whatever gap that opens unaddressed. No-op (and never shown) at any
    /// entry point other than the suggested-workout chooser, since only that
    /// flow supplies `onExcludeAndRegenerate`.
    private func regenerateAfterExcluding(_ exercise: Exercise) {
        guard let onExcludeAndRegenerate else { return }
        let candidateID = ExerciseSuggestionExclusionKey.forExercise(exercise)
        isRegeneratingAfterExclusion = true
        Task {
            let newPlan = await onExcludeAndRegenerate(candidateID)
            isRegeneratingAfterExclusion = false
            guard let newPlan else {
                regenerationFailed = true
                return
            }
            plan = newPlan
            originalPlan = newPlan
            resolvePartnerPlans()
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

    func saveAndStart() {
        // Starting from edit mode (every suggested-workout plan opens this
        // way) must commit whatever the user changed first — the same thing
        // the explicit Save button does — rather than silently discarding
        // it if the session that follows ever reads `originalPlan` again
        // (e.g. a subsequent Cancel on a re-presented editor).
        if isEditing {
            originalPlan = plan
            isEditing = false
        }
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

}
