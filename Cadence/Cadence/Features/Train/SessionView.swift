import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct SessionView: View {
    @Bindable var session: WorkoutSession
    var isManualLog: Bool = false
    var onDone: (() -> Void)? = nil
    var initiallyExpandedExerciseID: UUID? = nil
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    @Environment(AppSettings.self) var settings
    @Environment(AppModel.self) var model
    @Environment(ActiveWorkoutModel.self) var active

    @State var rest = RestTimerModel()
    @State var timers = WorkoutTimersModel()
    @State var pickerPresented = false
    @State var inlineExerciseID: UUID?
    @State var expandedExerciseID: UUID?
    @State var inlineExercise: Exercise?
    @State var inlineEditingSetID: UUID?
    @State var setEditorIdentity = UUID()
    @State var setEditorRoute: SetEditorRoute?
    @State var pendingRepsOverride: Int?
    @State var pendingPerformerID: UUID?
    @State var lastEffortMode: WatchEffortMode = .rpe
    @State var showWeightInfo = false
    @State var showDumbbellInfo = false
    @State var showKettlebellInfo = false
    @AppStorage("dumbbellInfoShown") var dumbbellInfoShown = false
    @AppStorage("kettlebellInfoShown") var kettlebellInfoShown = false
    @State var showDeleteConfirm = false
    @State var healthSaved = false
    @Query(sort: \Person.name) var allPeople: [Person]
    @State var addPartnerPresented = false
    @State var newPartnerName = ""
    @State var renamePresented = false
    @State var editedTitle = ""
    @State var datePickerPresented = false
    @State var endDatePickerPresented = false
    @State var exerciseToRemove: Exercise?
    @State var managePartnersPresented = false
    @State var watchdog = IdleWatchdog()
    @State var idlePromptShown = false
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var usePreviousPresented = false
    @State var swapTarget: ExerciseSwap.SwapTarget?
    @State var coolingDown = false
    @State var coolDownConfirm = false
    let idleTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @State var hrSamples: [HRSamplePoint] = []
    @State var cache = SessionHistoryCache()
    /// Each performer's rep pattern across every movement they have logged, keyed
    /// by `SessionRenderModel.performerKey`. Refreshed with the render cache, so a
    /// partner's usual reps cost one bounded history walk per structural change
    /// rather than a fetch per keystroke (field test 2026-08-19 #3).
    @State var generalRepLadders: [String: [[Int]]] = [:]
    /// Exercise rows resolved by name for the planned-only cards. Looking these up
    /// with `findOrCreateExercise` inside `body` fetched — and could insert — on
    /// every redraw (field test 2026-08-19 #4).
    @State var plannedExerciseIndex: [String: Exercise] = [:]
    /// Exercise the scroll view should bring to the top on the next redraw.
    @State var scrollTarget: UUID?
    /// Set after a save; consumed once the render cache contains the exercise's
    /// card, which may only appear on the rebuild that the save triggered.
    @State var pendingScrollExerciseID: UUID?
    var refreshSignature: SessionRenderModel.Signature {
        SessionRenderModel.signature(session: session, prRule: settings.prRule, formula: settings.formula)
    }
    var rosterEntries: [RosterEntry] {
        [RosterEntry(personID: nil, name: "Me", isMe: true)]
        + attributablePartners.map { RosterEntry(personID: $0.id, name: $0.name, isMe: false) }
    }

    var attributedPartnerIDs: [UUID] {
        (session.sets ?? []).compactMap { set in
            guard let p = set.performedBy, !p.isMe else { return nil }
            return p.id
        }
    }

    var roster: [Person] {
        SessionRoster.roster(activePartnerIDs: session.activePartnerIDs, allPeople: allPeople)
    }

    var attributablePartners: [Person] {
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
    /// Resolves the planned-only movements to their catalog rows once per
    /// structural change instead of once per redraw.
    private func indexedPlannedExercises() -> [String: Exercise] {
        let names = SessionViewModel.plannedOnlyNames(session: session)
        guard !names.isEmpty else { return [:] }
        var index: [String: Exercise] = [:]
        for name in names {
            if let ex = try? WorkoutRepository.findOrCreateExercise(named: name, in: context) {
                index[name] = ex
            }
        }
        return index
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

    private func openInlineEditor(for exercise: Exercise, editingSetID: UUID? = nil,
                                  repsOverride: Int? = nil, performerID: UUID? = nil) {
        inlineExerciseID = exercise.id
        inlineExercise = exercise
        inlineEditingSetID = editingSetID
        setEditorIdentity = editingSetID ?? UUID()
        pendingRepsOverride = repsOverride
        pendingPerformerID = performerID
        setEditorRoute = editingSetID.map { .edit(exerciseID: exercise.id, setID: $0) } ?? .add(exerciseID: exercise.id)
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
    private func inlineEditorConfig() -> InlineEditorConfig? {
        guard inlineExerciseID != nil, let exercise = inlineExercise else { return nil }
        let isEditing = inlineEditingSetID != nil
        let editingSet = isEditing ? session.orderedSets.first(where: { $0.id == inlineEditingSetID }) : nil
        if isEditing, editingSet == nil { return nil }
        let performerID: UUID? = isEditing
            ? (editingSet?.performedBy?.isMe ?? true ? nil : editingSet?.performedBy?.id)
            : (pendingPerformerID ?? nextPerson(for: exercise).flatMap { $0.isMe ? nil : $0.id })

        let defaults = performerDefaults(for: exercise)
        let own = defaults.first { $0.performerID == performerID }
        let weight: String
        let hint: Double?
        if isEditing, let set = editingSet {
            weight = Format.weightValue(set.weight, unit: settings.unit)
            hint = nil
        } else if let own, !own.weight.isEmpty {
            weight = own.weight
            hint = own.weightKg
        } else {
            let prescribedKg = isPrescribedMovement(exercise.name) ? session.prescribedLoadKg : 0
            weight = prescribedKg > 0 ? Format.weightValue(prescribedKg, unit: settings.unit) : ""
            hint = nil
        }
        let reps: Int
        if isEditing, let set = editingSet {
            reps = set.reps
        } else {
            reps = pendingRepsOverride ?? own?.reps ?? PerformerSetPlanner.defaultReps
        }
        let rpe: Int? = isEditing ? editingSet?.rpe.map { Int($0.rounded()) } : nil
        let bodyweight = isEditing ? (editingSet?.usesBodyweight ?? false) : isBodyweight(exercise)
        let workingSets = session.orderedSets.filter { $0.exercise?.id == exercise.id && !$0.isWarmup }
        let number = isEditing ? (workingSets.firstIndex(where: { $0.id == editingSet?.id }).map { $0 + 1 } ?? workingSets.count + 1) : workingSets.count + 1
        return InlineEditorConfig(
            id: isEditing ? (editingSet?.id ?? setEditorIdentity) : setEditorIdentity,
            isEditing: isEditing,
            weight: weight,
            reps: reps,
            rpe: rpe,
            bodyweight: bodyweight,
            performerID: performerID,
            roster: rosterEntries,
            hasPartners: hasPartners,
            unit: settings.unit,
            priorWeightHint: hint,
            performerDefaults: defaults,
            exerciseName: exercise.name,
            setNumberText: isEditing ? "Editing set \(number)" : "Set \(number) of \(max(number, session.plannedRepLadder.count))",
            recordedText: isEditing ? "Recorded" : nil,
            effortMode: lastEffortMode
        )
    }
    private func closeInlineEditor() {
        inlineExerciseID = nil
        inlineExercise = nil
        inlineEditingSetID = nil
        pendingRepsOverride = nil
        pendingPerformerID = nil
        setEditorRoute = nil
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
        expandedExerciseID = exercise.id
        pendingScrollExerciseID = exercise.id
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
    /// One row per roster member: what THEIR next set on this exercise should be,
    /// plus their own prior-session and this-session history so the editor's
    /// History card re-derives when the selected performer changes (2026-08-19 #2,
    /// 2026-08-20 issue 3).
    func performerDefaults(for exercise: Exercise) -> [InlineEditorConfig.PerformerDefault] {
        let ctx = cache.state.contexts.first { $0.exerciseID == exercise.id }
        return rosterEntries.map { entry in
            let performerID = entry.isMe ? nil : entry.personID
            let logged = loggedReps(for: exercise, performerID: performerID)
            let resolved = resolvedSet(for: exercise, setIndex: logged.count, performerID: performerID)
            let pc = ctx?.performerContexts.first { $0.performerID == performerID }
            let lastTime = pc.flatMap { SessionRenderModel.lastTimeSegment(label: $0.label, sets: $0.lastTimeSets, unit: settings.unit) }
            let lastSet = SetHistoryText.lastSetThisSession(loggedSets(for: exercise, performerID: performerID).last, unit: settings.unit)
            return InlineEditorConfig.PerformerDefault(
                performerID: performerID, reps: resolved.reps, weightKg: resolved.weightKg,
                weight: resolved.weightKg.map { Format.weightValue($0, unit: settings.unit) } ?? "",
                lastTimeText: lastTime, lastSetThisSession: lastSet)
        }
    }

    private func loggedSets(for exercise: Exercise, performerID: UUID?) -> [SetEntry] {
        session.orderedSets.filter { $0.exercise?.id == exercise.id && !$0.isWarmup && setPerformedBy($0, performerID: performerID) }.sorted { $0.order < $1.order }
    }

    private func loggedReps(for exercise: Exercise, performerID: UUID?) -> [Int] {
        loggedSets(for: exercise, performerID: performerID).map(\.reps)
    }

    /// The single resolution path shared with the session's pending rows, so the
    /// editor can never disagree with the row the user tapped to open it.
    private func resolvedSet(for exercise: Exercise, setIndex: Int,
                             performerID: UUID?) -> PerformerSetPlanner.Resolved {
        let explicit = session.explicitPlannedSets(forPerformerID: performerID,
                                                   exerciseName: exercise.name)
        let ownerPlan = session.explicitPlannedSets(forPerformerID: nil, exerciseName: exercise.name)
            ?? session.plannedRepLadder.map {
                PlannedSetPrescription(targetReps: $0,
                                       targetWeightKg: session.prescribedLoadKg > 0 ? session.prescribedLoadKg : nil)
            }
        var history = cache.state.performerHistory(forExerciseID: exercise.id, performerID: performerID)
        if history.repLadders.isEmpty {
            history.repLadders = WorkoutRepository.repLadderHistory(
                for: exercise, performedBy: people(for: performerID), excluding: session)
        }
        if history.firstWorkingWeightKg == nil {
            history.firstWorkingWeightKg = WorkoutRepository.firstWorkingSetWeight(
                for: exercise, performedBy: people(for: performerID), excluding: session)
        }
        if history.generalRepLadders.isEmpty {
            history.generalRepLadders = generalRepLadders[SessionRenderModel.performerKey(performerID)] ?? []
        }
        history.repsLoggedThisSession = loggedReps(for: exercise, performerID: performerID)
        // What they lifted for this movement *today* is a better starting load
        // than what they opened with last time.
        if let last = SessionViewModel.lastSessionWeight(session: session, exercise: exercise,
                                                         performerID: performerID) {
            history.firstWorkingWeightKg = last
        }
        return PerformerSetPlanner.resolve(
            setIndex: setIndex,
            performerPlan: explicit,
            ownerPlan: ownerPlan,
            // The coach ladder is the owner's prescription. A returning partner
            // gets their own established rep pattern instead.
            ownerLadder: SessionViewModel.effectiveLadder(session: session),
            isOwner: performerID == nil,
            history: history)
    }

    @ViewBuilder
    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.sectionSpacing)) {
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
                CadenceActionButton(title: "Use Previous Workout",
                                    systemImage: "clock.arrow.circlepath",
                                    tint: .accentColor) {
                    usePreviousPresented = true
                }
                .accessibilityIdentifier("session.usePrevious")

                ContentUnavailableView("Empty workout",
                                       systemImage: "dumbbell",
                                       description: Text("Use a previous workout, or add exercises below."))
            }

            ForEach(cache.state.contexts, id: \.exerciseID) { ctx in
                exerciseCardView(for: ctx)
                    .id(ctx.exerciseID)
            }
            ForEach(plannedOnlyNames, id: \.self) { name in
                plannedCard(name)
            }

            CadenceActionButton(title: "Add Exercise",
                                systemImage: "plus.circle.fill",
                                emphasis: .secondary) {
                pickerPresented = true
            }
            .accessibilityIdentifier("session.addExercise")

            if active.strengthSession?.id == session.id {
                WorkoutControlBar(
                    isPaused: active.isPaused,
                    onPauseToggle: togglePause,
                    onEnd: endWorkout,
                    onCoolDown: { coolDownConfirm = true },
                    confirmMessage: "This finishes and saves your workout."
                )
            } else if isManualLog {
                CadenceActionButton(title: "Done", systemImage: "checkmark") {
                    finishManualLog()
                }
                .accessibilityIdentifier("log.done")
            }
        }
        .padding(CGFloat(LayoutMetrics.pagePadding))

    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { scrollContent }
                // Saving a set returns here with that exercise expanded and pulled
                // to the top of the screen, so the next set is always what you are
                // looking at (field test 2026-08-19 #6).
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    if reduceMotion {
                        proxy.scrollTo(target, anchor: .top)
                    } else {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                    }
                    scrollTarget = nil
                }
        }
        .navigationTitle(session.title.isEmpty ? "Workout" : session.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            if active.strengthSession?.id == session.id {
                VStack(spacing: 0) {
                    WorkoutElapsedHeader(clock: active.clock, isPaused: active.isPaused, timers: $timers)
                    SessionLiveHRBand()
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
        .task(id: refreshSignature) {
            let recent = (try? WorkoutRepository.allSessions(context)) ?? []
            generalRepLadders = SessionRenderModel.generalRepLadders(recentSessions: recent,
                                                                     excluding: session)
            plannedExerciseIndex = indexedPlannedExercises()
            cache.refresh(signature: refreshSignature) {
                SessionRenderModel.build(session: session, prRule: settings.prRule,
                                         formula: settings.formula, allPeople: allPeople,
                                         recentSessions: recent)
            }
            if expandedExerciseID == nil {
                // Strength starts compact. Focused history review may opt into
                // one expanded exercise explicitly.
                expandedExerciseID = initiallyExpandedExerciseID
            }
            if let target = pendingScrollExerciseID,
               cache.state.contexts.contains(where: { $0.exerciseID == target }) {
                pendingScrollExerciseID = nil
                expandedExerciseID = target
                scrollTarget = target
            }
        }
        .onAppear {
            if expandedExerciseID == nil {
                expandedExerciseID = initiallyExpandedExerciseID
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
        .onChange(of: addPartnerPresented) { _, presented in
            guard !presented, inlineExercise != nil else { return }
            setEditorRoute = inlineEditingSetID.map { .edit(exerciseID: inlineExercise!.id, setID: $0) }
                ?? .add(exerciseID: inlineExercise!.id)
        }
        .sheet(isPresented: $usePreviousPresented) {
            PreviousWorkoutPicker(excluding: session) { past in
                _ = try? WorkoutRepository.copyWorkout(from: past, into: session, in: context)
                recordActivity()
            }
        }
        .sheet(isPresented: $showWeightInfo) { weightInfoSheet }
        .sheet(isPresented: $showDumbbellInfo) { dumbbellInfoSheet }
        .sheet(isPresented: $showKettlebellInfo) { kettlebellInfoSheet }
        .fullScreenCover(item: $setEditorRoute) { _ in
            if let cfg = inlineEditorConfig(), let ex = inlineExercise {
                InlineSetEditorView(config: cfg,
                                    wouldBePR: { [cache] kg, reps in cache.state.wouldBePR(weightKg: kg, reps: reps, isWarmup: false, rule: settings.prRule, formula: settings.formula, for: ex.id) },
                                    onSave: { draft in recordInlineSet(for: ex, draft: draft) },
                                    onDelete: inlineEditingSetID == nil ? nil : { deleteInlineSet() },
                                    onCancel: { closeInlineEditor() }, onActivity: { recordActivity() },
                                    onEffortMode: { lastEffortMode = $0 },
                                    onAddPartner: { setEditorRoute = nil; addPartnerPresented = true })
            } else { Color.clear }
        }
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
            isExpanded: expandedExerciseID == ctx.exerciseID,
            isCurrent: inlineExerciseID == ctx.exerciseID,
            compactSummary: compactSummary(for: ctx),
            onToggleExpansion: {
                if reduceMotion {
                    expandedExerciseID = expandedExerciseID == ctx.exerciseID ? nil : ctx.exerciseID
                } else { withAnimation(.easeInOut(duration: 0.18)) {
                    expandedExerciseID = expandedExerciseID == ctx.exerciseID ? nil : ctx.exerciseID
                } }
            },
            isInlineActive: isActive,
            inlineEditingSetID: inlineEditingSetID,
            inlineConfig: isActive ? inlineEditorConfig() : nil,
            wouldBePR: { [cache] kg, reps in
                cache.state.wouldBePR(weightKg: kg, reps: reps, isWarmup: false,
                                      rule: settings.prRule, formula: settings.formula,
                                      for: ctx.exerciseID)
            },
            onTapSet: { set in
                expandedExerciseID = ctx.exerciseID
                guard let ex = exerciseForID(ctx.exerciseID) else { return }
                openInlineEditor(for: ex, editingSetID: set.setID)
            },
            onTapPending: { pending in
                expandedExerciseID = ctx.exerciseID
                guard let ex = exerciseForID(ctx.exerciseID) else { return }
                openInlineEditor(for: ex, repsOverride: pending.targetReps, performerID: pending.performerID)
            },
            onRepeat: {
                guard let ex = exerciseForID(ctx.exerciseID) else { return }
                let sets = session.orderedSets.filter { $0.exercise?.id == ex.id }
                if let last = sets.last(where: {
                    if let next = nextPerson(for: ex) { return setPerformedBy($0, person: next) }
                    return $0.isOwnerSet
                }) ?? sets.last {
                    addSet(to: ex, weightKg: last.weight, reps: last.reps, rpe: last.rpe,
                           isWarmup: last.isWarmup, usesBodyweight: last.usesBodyweight,
                           note: nil, performedBy: nextPerson(for: ex))
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

    private func compactSummary(for ctx: SessionRenderModel.ExerciseContext) -> String {
        SessionRenderModel.compactSummary(context: ctx, unit: settings.unit)
    }

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
    @ViewBuilder
    private func plannedCard(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name).font(.headline)
                    .accessibilityIdentifier("exerciseCard.\(name)")
                Spacer()
                if let ex = plannedExerciseIndex[name] {
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
            if inlineExercise == nil || inlineExercise?.name != name {
                Button {
                    if let ex = plannedExerciseIndex[name]
                        ?? (try? WorkoutRepository.findOrCreateExercise(named: name, in: context)) {
                        openInlineEditor(for: ex)
                    }
                } label: { Label("Add Set", systemImage: "plus") }
                    .buttonStyle(.bordered).controlSize(.small)
                    .accessibilityIdentifier("set.add.\(name)")
            }
        }
        .padding(CGFloat(LayoutMetrics.cardPadding))
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded)
    }
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
            active.finishedSummary = FinishedSummary(data: .from(session: session, hrSamples: hrSamples), session: session)
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
    private func nextPerson(for exercise: Exercise) -> Person? {
        guard hasPartners else { return nil }
        let ctx = cache.state.contexts.first { $0.exerciseID == exercise.id }
        let rosterOrder: [UUID?] = rosterEntries.map { $0.isMe ? nil : $0.personID }
        let lastID = session.orderedSets
            .filter { $0.exercise?.id == exercise.id && !$0.isWarmup }
            .last.map { $0.isOwnerSet ? nil : $0.performedBy?.id } ?? nil
        let id = SetAlternation.nextPerformerID(pendingSets: ctx?.pendingSets ?? [],
                                                rosterOrder: rosterOrder,
                                                lastLoggedPerformerID: lastID)
        return id.flatMap { people(for: $0) } ?? allPeople.first { $0.isMe }
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
