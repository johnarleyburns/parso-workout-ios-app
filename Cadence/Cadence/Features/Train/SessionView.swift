import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct SessionView: View {
    @Bindable var session: WorkoutSession
    var isManualLog: Bool = false
    var onDone: (() -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @Environment(ActiveWorkoutModel.self) private var active

    @State private var rest = RestTimerModel()
    @State private var timers = WorkoutTimersModel()
    @State private var pickerPresented = false
    @State private var inlineExerciseID: UUID?
    @State private var inlineExercise: Exercise?
    @State private var inlineEditingSetID: UUID?
    @State private var showWeightInfo = false
    @State private var showDumbbellInfo = false
    @State private var showKettlebellInfo = false
    @AppStorage("dumbbellInfoShown") private var dumbbellInfoShown = false
    @AppStorage("kettlebellInfoShown") private var kettlebellInfoShown = false
    @State private var showDeleteConfirm = false
    @State private var healthSaved = false
    @Query(sort: \Person.name) var allPeople: [Person]
    @State var addPartnerPresented = false
    @State var newPartnerName = ""
    @State private var renamePresented = false
    @State private var editedTitle = ""
    @State private var datePickerPresented = false
    @State private var endDatePickerPresented = false
    @State private var exerciseToRemove: Exercise?
    @State var managePartnersPresented = false
    @State private var watchdog = IdleWatchdog()
    @State private var idlePromptShown = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var usePreviousPresented = false
    /// Phase E: unified swap target — dismissal never nils the payload.
    @State private var swapTarget: ExerciseSwap.SwapTarget?
    @State private var coolingDown = false
    @State private var coolDownConfirm = false
    private let idleTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @State private var hrSamples: [HRSamplePoint] = []
    /// Perf cache (launch-blockers Phase 2): rebuilds only when the signature
    /// (set count, order, roster, PR rule) changes — not on keystrokes.
    @State private var cache = SessionHistoryCache()
    // MARK: - Computed properties
    private var refreshSignature: SessionRenderModel.Signature {
        SessionRenderModel.signature(session: session, prRule: settings.prRule, formula: settings.formula)
    }
    private var rosterEntries: [RosterEntry] {
        [RosterEntry(personID: nil, name: "Me", isMe: true)]
        + attributablePartners.map { RosterEntry(personID: $0.id, name: $0.name, isMe: false) }
    }

    private var attributedPartnerIDs: [UUID] {
        (session.sets ?? []).compactMap { set in
            guard let p = set.performedBy, !p.isMe else { return nil }
            return p.id
        }
    }

    var roster: [Person] {
        SessionRoster.roster(activePartnerIDs: session.activePartnerIDs, allPeople: allPeople)
    }

    private var attributablePartners: [Person] {
        SessionRoster.attributablePartners(activePartnerIDs: session.activePartnerIDs,
                                           allPeople: allPeople,
                                           includingAttributed: attributedPartnerIDs)
    }

    var hasPartners: Bool {
        SessionRoster.canAttribute(activePartnerIDs: session.activePartnerIDs,
                                   allPeople: allPeople,
                                   attributedIDs: attributedPartnerIDs)
    }

    var recentPartners: [Person] {
        let sessions = (try? WorkoutRepository.allSessions(context)) ?? []
        var seen = Set<String>()
        var result: [Person] = []
        let scoped = Set(session.activePartnerIDs)
        for s in sessions.sorted(by: { $0.date > $1.date }) where s.id != session.id {
            for pid in s.activePartnerIDs {
                guard !seen.contains(pid), !scoped.contains(pid),
                      let p = allPeople.first(where: { $0.id.uuidString == pid }),
                      !p.isMe else { continue }
                seen.insert(pid)
                result.append(p)
            }
        }
        return result
    }

    private func isBodyweight(_ exercise: Exercise) -> Bool {
        SessionViewModel.isBodyweight(exercise)
    }

    private var plannedOnlyNames: [String] {
        SessionViewModel.plannedOnlyNames(session: session)
    }

    private var isEmptySession: Bool {
        SessionViewModel.isEmptySession(session: session)
    }

    private var plan: WorkoutPlan? {
        session.planKey.flatMap { PlanCatalog.plan(forKey: $0) }
    }

    private func prescription(for name: String) -> String? {
        SessionViewModel.prescription(for: name, session: session, plan: plan, unit: settings.unit)
    }

    private func isPrescribedMovement(_ name: String) -> Bool {
        SessionViewModel.isPrescribedMovement(name, session: session)
    }

    // MARK: - Inline editor helpers

    private func openInlineEditor(for exercise: Exercise, editingSetID: UUID? = nil, repsOverride: Int? = nil) {
        inlineExerciseID = exercise.id
        inlineExercise = exercise
        inlineEditingSetID = editingSetID

        if !dumbbellInfoShown, case .dumbbell = exercise.equipmentValue {
            dumbbellInfoShown = true
            showDumbbellInfo = true
        }
        if !kettlebellInfoShown, case .kettlebell = exercise.equipmentValue {
            kettlebellInfoShown = true
            showKettlebellInfo = true
        }
        recordActivity()
    }

    /// Builds the inline editor config from the cache + current session state.
    /// The cache only covers exercises with logged sets, so a planned-only card
    /// (first set of the session) falls back to direct history lookups.
    private func inlineEditorConfig() -> InlineEditorConfig? {
        guard let exerciseID = inlineExerciseID,
              let exercise = inlineExercise else { return nil }
        let cachedCtx = cache.state.contexts.first(where: { $0.exerciseID == exerciseID })

        let isEditing = inlineEditingSetID != nil
        let editingSet = isEditing ? session.orderedSets.first(where: { $0.id == inlineEditingSetID }) : nil
        // The edited set can vanish mid-edit (watch relay / cloud merge) — never force-unwrap it.
        if isEditing, editingSet == nil { return nil }

        let performerID: UUID? = isEditing
            ? (editingSet?.performedBy?.isMe ?? true ? nil : editingSet?.performedBy?.id)
            : nextPerson().flatMap { $0.isMe ? nil : $0.id }

        let pc = cachedCtx?.performerContexts.first { $0.performerID == performerID }
            ?? cachedCtx?.performerContexts.first { $0.isMe }

        let weight: String
        let hint: Double?
        if isEditing, let set = editingSet {
            weight = Format.weightValue(set.weight, unit: settings.unit)
            hint = nil
        } else {
            if let last = SessionViewModel.lastSessionWeight(session: session, exercise: exercise, performerID: performerID) {
                weight = Format.weightValue(last, unit: settings.unit)
                hint = nil
            } else if let firstPrior = pc?.firstWorkingWeightKg
                        ?? WorkoutRepository.firstWorkingSetWeight(for: exercise, performedBy: people(for: performerID), excluding: session) {
                weight = Format.weightValue(firstPrior, unit: settings.unit)
                hint = firstPrior
            } else {
                let prescribedKg = isPrescribedMovement(exercise.name) ? session.prescribedLoadKg : 0
                weight = prescribedKg > 0 ? Format.weightValue(prescribedKg, unit: settings.unit) : ""
                hint = nil
            }
        }

        let reps: Int
        if isEditing, let set = editingSet {
            reps = set.reps
        } else {
            let loggedCount = session.orderedSets.filter {
                $0.exercise?.id == exercise.id && !$0.isWarmup && setPerformedBy($0, performerID: performerID)
            }.count
            reps = plannedReps(for: exercise, setIndex: loggedCount, performerID: performerID)
        }

        let rpe: Int? = isEditing ? editingSet?.rpe.map { Int($0.rounded()) } : nil
        let bodyweight = isEditing ? (editingSet?.usesBodyweight ?? false) : isBodyweight(exercise)

        return InlineEditorConfig(
            id: isEditing ? (editingSet?.id ?? UUID()) : UUID(),
            isEditing: isEditing,
            weight: weight,
            reps: reps,
            rpe: rpe,
            bodyweight: bodyweight,
            performerID: performerID,
            roster: rosterEntries,
            hasPartners: hasPartners,
            unit: settings.unit,
            priorWeightHint: hint
        )
    }

    private func closeInlineEditor() {
        inlineExerciseID = nil
        inlineExercise = nil
        inlineEditingSetID = nil
    }

    private func recordInlineSet(for exercise: Exercise, draft: SetDraft) {
        let kg = SessionViewModel.canonicalKg(input: draft.weightString, unit: draft.unit,
                                              plateRounding: settings.plateRounding)
        let rpe = draft.rpe.map(Double.init)
        if let editingSetID = inlineEditingSetID,
           let editing = session.orderedSets.first(where: { $0.id == editingSetID }) {
            try? WorkoutRepository.updateSet(editing, weightKg: kg, reps: draft.reps,
                                             rpe: .some(rpe),
                                             usesBodyweight: draft.bodyweight,
                                             performedBy: .some(people(for: draft.performerID)),
                                             in: context)
        } else {
            addSet(to: exercise, weightKg: kg, reps: draft.reps, rpe: rpe, isWarmup: false,
                   usesBodyweight: draft.bodyweight, note: nil, performedBy: people(for: draft.performerID))
        }
        closeInlineEditor()
    }

    private func deleteInlineSet() {
        guard let setID = inlineEditingSetID,
              let set = session.orderedSets.first(where: { $0.id == setID }) else { return }
        try? WorkoutRepository.deleteSet(set, in: context)
        closeInlineEditor()
    }

    private func people(for id: UUID?) -> Person? {
        guard let id else { return nil }
        return allPeople.first { $0.id == id }
    }

    private func exerciseForID(_ id: UUID) -> Exercise? {
        session.exercisesInOrder.first { $0.id == id }
    }

    private func setPerformedBy(_ set: SetEntry, performerID: UUID?) -> Bool {
        SessionViewModel.setPerformedBy(set, performerID: performerID)
    }

    private func setPerformedBy(_ set: SetEntry, person: Person) -> Bool {
        person.isMe ? set.isOwnerSet : (set.performedBy?.id == person.id)
    }

    private func plannedReps(for exercise: Exercise, setIndex: Int, performerID: UUID?) -> Int {
        let currentReps = session.orderedSets
            .filter { $0.exercise?.id == exercise.id && !$0.isWarmup && setPerformedBy($0, performerID: performerID) }
            .sorted { $0.order < $1.order }
            .map { $0.reps }
        let performer = people(for: performerID)
        let prior = WorkoutRepository.repLadderHistory(for: exercise, performedBy: performer, excluding: session)
        let lastLogged = session.orderedSets.last(where: {
            $0.exercise?.id == exercise.id && !$0.isWarmup && setPerformedBy($0, performerID: performerID)
        })?.reps
        return SessionViewModel.plannedReps(
            ladder: SessionViewModel.effectiveLadder(session: session),
            setIndex: setIndex,
            currentSessionReps: currentReps,
            priorSessionLadders: prior,
            lastLoggedReps: lastLogged)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isManualLog { loggedDateBanner }
                if active.strengthSession?.id != session.id && !isManualLog {
                    editableMetadataRow
                }
                if rest.isRunning {
                    RestTimerBar(model: rest) { Haptics.restComplete() }
                }
                if let plan { planBanner(plan) }
                partnerBar

                if isEmptySession {
                    Button {
                        usePreviousPresented = true
                    } label: {
                        Label("Use Previous Workout", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("session.usePrevious")

                    ContentUnavailableView("Empty workout",
                                           systemImage: "dumbbell",
                                           description: Text("Use a previous workout, or add exercises below."))
                        .padding(.top, 16)
                }

                ForEach(cache.state.contexts, id: \.exerciseID) { ctx in
                    exerciseCardView(for: ctx)
                }
                ForEach(plannedOnlyNames, id: \.self) { name in
                    plannedCard(name)
                }

                Button {
                    pickerPresented = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.top, 4)
                .accessibilityIdentifier("session.addExercise")

                if active.strengthSession?.id == session.id {
                    WorkoutControlBar(
                        isPaused: active.isPaused,
                        onPauseToggle: togglePause,
                        onEnd: endWorkout,
                        onCoolDown: { coolDownConfirm = true },
                        confirmMessage: "This finishes and saves your workout."
                    )
                    .padding(.top, 8)
                } else if isManualLog {
                    Button {
                        finishManualLog()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(.green).controlSize(.large)
                    .padding(.top, 8)
                    .accessibilityIdentifier("log.done")
                }
            }
            .padding()
        }
        .navigationTitle(session.title.isEmpty ? "Workout" : session.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            if active.strengthSession?.id == session.id {
                VStack(spacing: 0) {
                    WorkoutElapsedHeader(clock: active.clock, isPaused: active.isPaused, timers: $timers)
                    if model.hrm.currentBPM != nil { liveHRBand }
                }
            }
        }
        .toolbar { toolbarContent }
        .overlay(alignment: .top) {
            if healthSaved {
                Text("Saved to Apple Health")
                    .font(.caption).padding(8)
                    .cadenceGlass(in: Capsule(), fallback: .thinMaterial)
                    .accessibilityIdentifier("session.healthSaved")
            }
        }
        .keepAwake(!isManualLog)
        .simultaneousGesture(TapGesture().onEnded { recordActivity() })
        .task(id: refreshSignature) {
            cache.refresh(signature: refreshSignature) {
                SessionRenderModel.build(session: session, prRule: settings.prRule,
                                         formula: settings.formula, allPeople: allPeople)
            }
        }
        .sheet(isPresented: $pickerPresented) {
            ExercisePickerView { exercise in
                if !session.exercisesInOrder.contains(where: { $0.id == exercise.id }) &&
                   !session.plannedExerciseNames.contains(exercise.name) {
                    session.plannedExerciseNames.append(exercise.name)
                    try? context.save()
                }
                openInlineEditor(for: exercise)
            }
        }
        .sheet(item: $swapTarget) { target in
            let pickAction: ExercisePickerView.PickAction = {
                switch target {
                case .logged: return .use
                case .planned: return .swap
                }
            }()
            ExercisePickerView(action: pickAction) { picked in
                switch target {
                case .planned(let oldName):
                    swapPlannedExercise(oldName: oldName, newName: picked.name)
                case .logged(let exerciseID):
                    if let old = exerciseForID(exerciseID), old.id != picked.id {
                        _ = try? WorkoutRepository.changeExercise(in: session, from: old, to: picked, in: context)
                        recordActivity()
                    }
                }
            }
        }
        .sheet(isPresented: $managePartnersPresented) { managePartnersSheet }
        .sheet(isPresented: $addPartnerPresented) { addPartnerSheet }
        .sheet(isPresented: $usePreviousPresented) {
            PreviousWorkoutPicker(excluding: session) { past in
                _ = try? WorkoutRepository.copyWorkout(from: past, into: session, in: context)
                recordActivity()
            }
        }
        .sheet(isPresented: $showWeightInfo) { weightInfoSheet }
        .sheet(isPresented: $showDumbbellInfo) { dumbbellInfoSheet }
        .sheet(isPresented: $showKettlebellInfo) { kettlebellInfoSheet }
        .fullScreenCover(isPresented: $coolingDown) {
            GuidedPhaseOverlay(
                title: "Cool Down",
                minutes: session.cooldownSeconds > 0 ? Int(session.cooldownSeconds / 60) : settings.cooldownMinutes,
                tint: .teal,
                idPrefix: "cooldown",
                soundsEnabled: settings.workoutSounds,
                onFinish: { secs in
                    session.cooldownSeconds = Double(secs)
                    coolingDown = false
                    endWorkout()
                })
        }
        .confirmationDialog("Start cool-down?", isPresented: $coolDownConfirm, titleVisibility: .visible) {
            Button("Start Cool Down") { active.pause(); coolingDown = true }
                .accessibilityIdentifier("workout.coolDownConfirm")
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This ends your workout and starts the cool-down timer.")
        }
        .task { _ = try? WorkoutRepository.me(in: context) }
        .onAppear {
            guard !isManualLog, model.watchAvailable else { return }
            if case .connected = model.hrm.state { return }
            model.startWatchStrength()
        }
        .onDisappear { if isManualLog { cleanupEmptyLog() } }
        .onReceive(idleTimer) { _ in
            handleIdleTick()
            if active.strengthSession?.id == session.id {
                sampleHR()
                active.writeHeartbeat()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            recordActivity()
        }
        .alert("Still training?", isPresented: $idlePromptShown) {
            Button("Keep going") { recordActivity() }
            Button("Save now", role: .destructive) { endWorkout() }
        } message: {
            Text("No activity for \(settings.idleTimeoutMinutes) min. Your workout will pause — it never ends on its own.")
        }
        .alert("Rename workout", isPresented: $renamePresented) {
            TextField("Title", text: $editedTitle).accessibilityIdentifier("rename.field")
            Button("Save") {
                session.title = editedTitle.trimmingCharacters(in: .whitespaces)
                try? context.save()
            }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog("Delete this workout?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let wasActive = active.strengthSession?.id == session.id
                if wasActive { active.endStrength(); active.minimize() }
                try? WorkoutRepository.softDeleteSession(session, in: context)
                if !wasActive { dismiss() }
            }
            .accessibilityIdentifier("session.deleteConfirm")
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All sets and exercises in this session will be removed. You can restore it from History → View Deleted.")
        }
        .sheet(isPresented: $datePickerPresented) {
            NavigationStack {
                DatePicker("Workout date", selection: Binding(
                    get: { session.date },
                    set: { session.date = $0; try? context.save()
                           NotificationCenter.default.post(name: .workoutHistoryChanged, object: nil) }
                ))
                .datePickerStyle(.graphical).padding()
                .navigationTitle("Edit Date").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { datePickerPresented = false } } }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $endDatePickerPresented) {
            NavigationStack {
                DatePicker("End time", selection: Binding(
                    get: { session.endedAt ?? session.date },
                    set: { session.endedAt = $0; try? context.save() }
                ))
                .datePickerStyle(.graphical).padding()
                .navigationTitle("Edit End Time").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { endDatePickerPresented = false } } }
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog("Remove this exercise?", isPresented: Binding(
            get: { exerciseToRemove != nil },
            set: { if !$0 { exerciseToRemove = nil } }
        ), titleVisibility: .visible) {
            Button("Remove exercise and all its sets", role: .destructive) {
                if let ex = exerciseToRemove {
                    _ = try? WorkoutRepository.removeExercise(ex, from: session, in: context)
                    recordActivity()
                }
                exerciseToRemove = nil
            }
            Button("Cancel", role: .cancel) { exerciseToRemove = nil }
        }
    }

    // MARK: - Exercise card (using cache + ExerciseCardView)

    @ViewBuilder
    private func exerciseCardView(for ctx: SessionRenderModel.ExerciseContext) -> some View {
        let isActive = inlineExerciseID == ctx.exerciseID
        let exercise = exerciseForID(ctx.exerciseID)

        ExerciseCardView(
            context: ctx,
            prSetIDs: cache.state.prSetIDs,
            roster: rosterEntries,
            hasPartners: hasPartners,
            unit: settings.unit,
            prRule: settings.prRule,
            prescriptionText: exercise.map { prescription(for: $0.name) } ?? nil,
            isInlineActive: isActive,
            inlineEditingSetID: inlineEditingSetID,
            inlineConfig: isActive ? inlineEditorConfig() : nil,
            wouldBePR: { [cache] kg, reps in
                cache.state.wouldBePR(weightKg: kg, reps: reps, isWarmup: false,
                                      rule: settings.prRule, formula: settings.formula,
                                      for: ctx.exerciseID)
            },
            onTapSet: { set in
                guard let ex = exerciseForID(ctx.exerciseID) else { return }
                openInlineEditor(for: ex, editingSetID: set.setID)
            },
            onTapPending: { reps in
                guard let ex = exerciseForID(ctx.exerciseID) else { return }
                openInlineEditor(for: ex, repsOverride: reps)
            },
            onRepeat: {
                guard let ex = exerciseForID(ctx.exerciseID) else { return }
                let sets = session.orderedSets.filter { $0.exercise?.id == ex.id }
                if let last = sets.last(where: {
                    if let next = nextPerson() { return setPerformedBy($0, person: next) }
                    return $0.isOwnerSet
                }) ?? sets.last {
                    addSet(to: ex, weightKg: last.weight, reps: last.reps, rpe: last.rpe,
                           isWarmup: last.isWarmup, usesBodyweight: last.usesBodyweight,
                           note: nil, performedBy: nextPerson())
                }
            },
            onAddSet: {
                guard let ex = exerciseForID(ctx.exerciseID) else { return }
                openInlineEditor(for: ex)
            },
            onChangeExercise: {
                if let ex = exerciseForID(ctx.exerciseID) { swapTarget = .logged(exerciseID: ex.id) }
            },
            onRemoveExercise: {
                if let ex = exerciseForID(ctx.exerciseID) { exerciseToRemove = ex }
            },
            exercise: exerciseForID(ctx.exerciseID),
            onSaveSet: { draft in
                guard let ex = exerciseForID(ctx.exerciseID) else { return }
                recordInlineSet(for: ex, draft: draft)
            },
            onDeleteEditingSet: { deleteInlineSet() },
            onDeleteSet: { set in
                guard let entry = session.orderedSets.first(where: { $0.id == set.setID }) else { return }
                try? WorkoutRepository.deleteSet(entry, in: context)
                recordActivity()
            },
            onCancelInline: { closeInlineEditor() },
            onActivity: { recordActivity() }
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if active.strengthSession?.id == session.id {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    active.minimize()
                } label: { Image(systemName: "chevron.down") }
                    .accessibilityIdentifier("session.minimize")
                    .accessibilityLabel("Minimize workout")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                if let plan {
                    NavigationLink {
                        RoutineDetailView(plan: plan, onEditorStart: { _ in })
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityIdentifier("session.info")
                    .accessibilityLabel("Workout details")
                }
                Button {
                    showDeleteConfirm = true
                } label: { Image(systemName: "trash") }
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("session.delete")
                    .accessibilityLabel("Delete workout")
                Button {
                    editedTitle = session.title; renamePresented = true
                } label: { Image(systemName: "pencil") }
                    .accessibilityIdentifier("session.rename")
                    .accessibilityLabel("Rename workout")
                Button {
                    Task { await saveToHealth() }
                } label: {
                    Image(systemName: healthSaved ? "checkmark.circle.fill" : "heart.text.square")
                }
                .disabled(session.orderedSets.isEmpty)
                .accessibilityIdentifier("session.saveHealth")
                .accessibilityLabel(healthSaved ? "Saved to Apple Health" : "Save workout to Apple Health")
            }
        }
    }

    // MARK: - Planned (reused) exercise card — no sets yet

    @ViewBuilder
    private func plannedCard(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name).font(.headline)
                    .accessibilityIdentifier("exerciseCard.\(name)")
                Spacer()
                if let ex = try? WorkoutRepository.findOrCreateExercise(named: name, in: context) {
                    NavigationLink {
                        ExerciseDetailView(exercise: ex)
                    } label: {
                        Image(systemName: "info.circle").font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("exercise.info.\(name)")
                    .accessibilityLabel("\(name) details")
                }
                Menu {
                    Button { swapTarget = .planned(name: name) } label: {
                        Label("Swap", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(role: .destructive) {
                        try? WorkoutRepository.removePlannedExercise(named: name, from: session, in: context)
                        recordActivity()
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.headline)
                        .foregroundStyle(.secondary).frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("planned.menu.\(name)")
                .accessibilityLabel("Planned exercise options")
            }
            if let rx = prescription(for: name) {
                Text(rx).font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("session.rx.\(name)")
            } else {
                Text("Planned — tap to log").font(.caption).foregroundStyle(.secondary)
            }
            if let ex = inlineExercise, ex.name == name, let cfg = inlineEditorConfig() {
                InlineSetEditorView(
                    config: cfg,
                    wouldBePR: { [cache] kg, reps in
                        cache.state.wouldBePR(weightKg: kg, reps: reps, isWarmup: false,
                                              rule: settings.prRule, formula: settings.formula,
                                              for: ex.id)
                    },
                    onSave: { draft in recordInlineSet(for: ex, draft: draft) },
                    onDelete: inlineEditingSetID != nil ? { deleteInlineSet() } : nil,
                    onCancel: { closeInlineEditor() },
                    onActivity: { recordActivity() })
            } else {
                Button {
                    if let ex = try? WorkoutRepository.findOrCreateExercise(named: name, in: context) {
                        openInlineEditor(for: ex)
                    }
                } label: { Label("Add Set", systemImage: "plus") }
                    .buttonStyle(.bordered).controlSize(.small)
                    .accessibilityIdentifier("set.add.\(name)")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Partner bar

    private var partnerBar: some View {
        HStack(spacing: 8) {
            Text("With:").font(.caption).foregroundStyle(.secondary)
            ForEach(roster) { p in
                performerChip(p)
                    .contextMenu {
                        if !p.isMe {
                            Button(role: .destructive) {
                                var ids = session.activePartnerIDs
                                ids.removeAll { $0 == p.id.uuidString }
                                session.activePartnerIDs = normalizedRosterIDs(ids)
                                try? context.save()
                            } label: { Label("Remove from session", systemImage: "person.slash") }
                        }
                    }
                if !p.isMe {
                    Text(p.name).font(.caption.weight(.medium)).padding(.horizontal, 6)
                }
            }
            Button {
                addPartnerPresented = true
            } label: { Image(systemName: "plus.circle") }
                .accessibilityIdentifier("partner.add").accessibilityLabel("Add training partner")
            Button {
                managePartnersPresented = true
            } label: { Image(systemName: "gearshape") }
                .accessibilityIdentifier("partner.manage").accessibilityLabel("Manage training partners")
            Spacer()
        }
    }

    // MARK: - Misc view helpers (charts, info sheets, etc.)

    private func planBanner(_ plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plan.schemeSummary).font(.headline)
                .accessibilityIdentifier("session.planBanner")
            if let notes = plan.notes {
                Text(notes).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
    }

    private var loggedDateBanner: some View {
        Button { datePickerPresented = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                Text("Logging \(session.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "calendar").font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("log.dateBanner")
    }

    private var editableMetadataRow: some View {
        HStack(spacing: 16) {
            Button { datePickerPresented = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar").font(.caption)
                    Text(session.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline)
                }.foregroundStyle(.tint)
            }
            .buttonStyle(.plain).accessibilityIdentifier("session.editDate")
            if session.endedAt != nil {
                Button { endDatePickerPresented = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock").font(.caption)
                        if let end = session.endedAt {
                            Text(Format.duration(end.timeIntervalSince(session.date))).font(.subheadline)
                        }
                    }.foregroundStyle(.tint)
                }
                .buttonStyle(.plain).accessibilityIdentifier("session.editEndTime")
            }
            Spacer()
        }
    }

    private var liveHRBand: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill").font(.caption).foregroundStyle(.red)
            if let bpm = model.hrm.currentBPM {
                Text("\(Int(bpm)) bpm").font(.caption.weight(.medium)).monospacedDigit()
            }
            if let battery = model.hrm.battery {
                Image(systemName: battery <= 10 ? "battery.0" : "battery.75")
                    .font(.caption2).foregroundStyle(battery <= 10 ? .red : .secondary)
                Text("\(battery)%").font(.caption2).foregroundStyle(.secondary)
            }
            if model.hrm.criticalBattery {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .cadenceGlass(in: Rectangle(), fallback: .ultraThinMaterial)
    }

    func performerChip(_ p: Person?) -> some View {
        let label = (p?.isMe ?? true) ? "M" : String((p?.name ?? "?").prefix(1)).uppercased()
        let palette: [Color] = [.purple, .teal, .pink, .indigo, .orange, .mint]
        let color: Color = {
            guard let p, !p.isMe else { return .accentColor }
            return palette[abs(p.id.hashValue) % palette.count]
        }()
        return Text(label)
            .font(.caption2.weight(.semibold)).foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(color, in: Circle())
            .accessibilityIdentifier("set.performer.\((p?.isMe ?? true) ? "Me" : (p?.name ?? "?"))")
    }

    // MARK: - Weight info sheets

    private var weightInfoSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if let ex = inlineExercise {
                    switch ex.resolvedLoadAccountingMode {
                    case .barbell:
                        Text("Barbell Weight").font(.headline)
                        Text("Enter the added plate load only. The bar weight (\(Format.weight(ex.effectiveDefaultBarWeightKg, unit: settings.unit))) is added automatically for calculations.\n\nEnter 0 when using only the bar or bodyweight. Bar weight is added separately for barbell calculations.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case .bodyweight:
                        Text("Bodyweight Exercise").font(.headline)
                        Text("Enter 0 when using only your bodyweight. Enter a positive value for added weight (e.g., weighted vest, dip belt).\n\nThe app tracks added load; bodyweight is yours alone.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case .dualDumbbell, .isolateralDumbbell:
                        Text("Dumbbell Weight").font(.headline)
                        Text("Enter the weight of one dumbbell. The app accounts for paired, single, and isolateral dumbbell movements in calculations.\n\nFor standard two-dumbbell exercises (bench press, curls, etc.), your entered weight is doubled automatically.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case .singleDumbbell:
                        Text("Dumbbell Weight").font(.headline)
                        Text("Enter the weight of the single dumbbell used. This exercise uses one dumbbell at a time (e.g., goblet squat, skullcrusher).\n\nThe entered weight is used as-is for calculations.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case .dualKettlebell, .isolateralKettlebell:
                        Text("Kettlebell Weight").font(.headline)
                        Text("Enter the weight of one kettlebell. The app accounts for paired and single kettlebell movements in calculations.\n\nFor standard two-kettlebell exercises (double cleans, double presses, front squats, etc.), your entered weight is doubled automatically.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case .singleKettlebell:
                        Text("Kettlebell Weight").font(.headline)
                        Text("Enter the weight of the single kettlebell used. This exercise uses one kettlebell at a time (e.g., swing, snatch, Turkish get-up).\n\nThe entered weight is used as-is for calculations.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case nil:
                        Text("Weight Entry").font(.headline)
                        Text("Enter the weight as you would normally. This exercise uses standard weight accounting — what you enter is what's used for PRs, volume, and trends.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Weight Entry").font(.headline)
                    Text("Enter the weight you lifted. For barbell exercises, enter the plate load — the bar weight is added automatically. For dumbbell and kettlebell exercises, enter the weight of one dumbbell or kettlebell.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationTitle("Weight Help").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showWeightInfo = false } } }
        }
        .presentationDetents([.medium])
    }

    private var kettlebellInfoSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Kettlebell Weight Entry").font(.headline)
                Text("For kettlebell exercises, enter the weight of a single kettlebell — the app handles the accounting automatically:\n\n• **Two-kettlebell exercises** like double kettlebell cleans or presses: your entered weight is doubled for calculations (you're lifting two of them).\n\n• **Single-kettlebell exercises** like swings, snatches, or Turkish get-ups: your entered weight is used as-is.\n\nThis way you can always enter what's printed on the kettlebell, and the math works correctly behind the scenes.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Kettlebell Help").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Got it") { showKettlebellInfo = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var dumbbellInfoSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Dumbbell Weight Entry").font(.headline)
                Text("For dumbbell exercises, enter the weight of a single dumbbell — the app handles the accounting automatically:\n\n• **Two-dumbbell exercises** like bench press or curls: your entered weight is doubled for calculations (you're lifting two of them).\n\n• **Single-dumbbell exercises** like goblet squats or skullcrushers: your entered weight is used as-is.\n\n• **Isolateral exercises** like one-arm rows: your entered weight is doubled for comparison against barbell movements.\n\nThis way you can always enter what's printed on the dumbbell, and the math works correctly behind the scenes.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Dumbbell Help").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Got it") { showDumbbellInfo = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Actions

    private func recordActivity() {
        watchdog.recordActivity()
        guard active.strengthSession?.id == session.id else { return }
        active.recordActivityAutoResume()
    }

    private func handleIdleTick() {
        guard active.strengthSession?.id == session.id else { return }
        switch watchdog.tick(now: Date(),
                             timeoutMinutes: settings.idleTimeoutMinutes,
                             isPaused: active.isPaused,
                             enabled: settings.autoEndOnIdle) {
        case .showPrompt: idlePromptShown = true
        case .autoPause: idlePromptShown = false; active.pause(origin: .auto)
        case .none: break
        }
    }

    private func togglePause() {
        if active.isPaused { active.resume(); watchdog.recordActivity() }
        else { active.pause(origin: .manual) }
    }

    private func endWorkout() {
        WorkoutCues.endBeepSequence(enabled: settings.workoutSounds)
        model.stopWatchWorkout()
        if settings.autoSaveHealth, session.healthKitWorkoutUUID == nil, !session.orderedSets.isEmpty {
            Task { await saveToHealth() }
        }
        active.endStrength()
        try? context.save()
        Task { @MainActor in
            await Task.yield()
            active.finishedSummary = FinishedSummary(data: .from(session: session, hrSamples: hrSamples))
        }
    }

    private func sampleHR() {
        guard let bpm = model.hrm.currentBPM, bpm > 0 else { return }
        let now = Date().timeIntervalSince(session.date)
        hrSamples.append(HRSamplePoint(t: now, bpm: bpm))
    }

    private func saveToHealth() async {
        let sets = session.orderedSets
        guard let first = sets.first?.completedAt else { return }
        let last = sets.last?.completedAt ?? first
        let end = max(last, first.addingTimeInterval(60))
        let minutes = end.timeIntervalSince(first) / 60
        let kcal = max(30, round(CardioMath.strengthCaloriesPerMinute * minutes))
        let bpmValues = hrSamples.map(\.bpm)
        let summary = StrengthWorkoutSummary(
            id: session.id, start: first, end: end,
            activeEnergyKcal: kcal, hrSamples: hrSamples,
            avgHR: bpmValues.isEmpty ? nil : bpmValues.reduce(0, +) / Double(bpmValues.count),
            maxHR: bpmValues.max())
        let hkID = await model.health.saveStrengthWorkout(summary)
        if let hkID { session.healthKitWorkoutUUID = hkID; try? context.save() }
        withAnimation { healthSaved = true }
    }

    private func finishManualLog() { cleanupEmptyLog(); Haptics.selection(); onDone?() }

    private func cleanupEmptyLog() {
        guard isManualLog, session.orderedSets.isEmpty else { return }
        context.delete(session); try? context.save()
    }

    private func swapPlannedExercise(oldName: String, newName: String) {
        guard oldName != newName else { return }
        var names = session.plannedExerciseNames
        if let idx = names.firstIndex(of: oldName) { names[idx] = newName }
        session.plannedExerciseNames = names
        _ = try? WorkoutRepository.findOrCreateExercise(named: newName, in: context)
        try? context.save()
        recordActivity()
    }

    // MARK: - Partner roster helpers

    func togglePartnerScope(_ p: Person) {
        var ids = explicitRosterIDs()
        if let idx = ids.firstIndex(of: p.id.uuidString) { ids.remove(at: idx) }
        else { ids.append(p.id.uuidString) }
        session.activePartnerIDs = normalizedRosterIDs(ids)
        try? context.save()
    }

    func addAndScopePartner() {
        let name = newPartnerName.trimmingCharacters(in: .whitespaces)
        defer { newPartnerName = "" }
        guard !name.isEmpty,
              let p = try? WorkoutRepository.findOrCreatePerson(named: name, in: context) else { return }
        var ids = explicitRosterIDs()
        if !ids.contains(p.id.uuidString) { ids.append(p.id.uuidString); session.activePartnerIDs = normalizedRosterIDs(ids); try? context.save() }
    }

    private func nextPerson() -> Person? {
        guard hasPartners else { return nil }
        let ordered = roster
        guard !ordered.isEmpty else { return nil }
        guard let last = session.orderedSets.reversed().first(where: { set in
            ordered.contains { setPerformedBy(set, person: $0) }
        }), let lastIndex = ordered.firstIndex(where: { setPerformedBy(last, person: $0) }) else {
            return ordered.first
        }
        return ordered[(lastIndex + 1) % ordered.count]
    }

    private func explicitRosterIDs() -> [String] {
        let current = session.activePartnerIDs
        guard hasPartners else { return current }
        let ids = roster.map { $0.id.uuidString }
        return ids.isEmpty ? current : ids
    }

    private func normalizedRosterIDs(_ ids: [String]) -> [String] {
        let valid = Set(allPeople.map { $0.id.uuidString })
        var seen = Set<String>()
        let cleaned = ids.filter { valid.contains($0) && seen.insert($0).inserted }
        let partnerIDs = Set(allPeople.filter { !$0.isMe }.map { $0.id.uuidString })
        return cleaned.contains(where: { partnerIDs.contains($0) }) ? cleaned : []
    }

    func moveRosterMember(from index: Int, by offset: Int) {
        var ids = explicitRosterIDs()
        let target = index + offset
        guard ids.indices.contains(index), ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
        session.activePartnerIDs = normalizedRosterIDs(ids)
        try? context.save()
    }

    private func addSet(to exercise: Exercise, weightKg: Double, reps: Int,
                        rpe: Double?, isWarmup: Bool, usesBodyweight: Bool = false,
                        note: String?, performedBy: Person? = nil) {
        recordActivity()
        let person = (performedBy?.isMe ?? true) ? nil : performedBy
        let isPR = person == nil && WorkoutRepository.wouldBePR(exercise: exercise, weightKg: weightKg, reps: reps,
                                               isWarmup: isWarmup, rule: settings.prRule, formula: settings.formula)
        let when = session.isLogged ? session.date : Date()
        _ = try? WorkoutRepository.addSet(to: session, exercise: exercise, weightKg: weightKg,
                                          reps: reps, rpe: rpe, isWarmup: isWarmup,
                                          usesBodyweight: usesBodyweight, note: note,
                                          completedAt: when, performedBy: person, in: context)
        if isPR { Haptics.prAchieved() } else { Haptics.setLogged() }
        if settings.autoStartRest && !isWarmup && !isManualLog && active.strengthSession?.id == session.id {
            rest.start(seconds: settings.restSeconds)
        }
    }
}

struct PreviousWorkoutPicker: View {
    let excluding: WorkoutSession
    let onPick: (WorkoutSession) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    private var candidates: [WorkoutSession] {
        sessions.filter { $0.id != excluding.id && !$0.orderedSets.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    ContentUnavailableView("No previous workouts", systemImage: "clock",
                                           description: Text("Log a workout first."))
                }
                ForEach(candidates) { s in
                    Button {
                        onPick(s); dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title.isEmpty ? "Workout" : s.title)
                            Text(s.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                            Text("\(s.exercisesInOrder.count) exercises · \(s.orderedSets.count) sets")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("usePrevious.row")
                }
            }
            .navigationTitle("Use Previous Workout").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("usePrevious.cancel")
                }
            }
        }
    }
}
