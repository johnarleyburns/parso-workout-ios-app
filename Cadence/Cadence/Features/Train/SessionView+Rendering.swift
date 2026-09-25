import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension SessionView {
    @ViewBuilder
    var scrollContent: some View {
        VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.sectionSpacing)) {
            sessionTitleHeader
            if isActiveSession {
                LiveWorkoutVolumeSummary(state: liveVolumeState,
                                         expanded: $liveVolumeExpanded,
                                         performers: liveVolumePerformers,
                                         performerStates: liveVolumePerformerStates)
            }
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

            suggestExerciseButton

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
        .navigationTitle("")
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
            if let prMoment {
                prMomentCard(prMoment)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .zIndex(2)
            } else if healthSaved {
                Text("Saved to Apple Health")
                    .font(.caption).padding(8)
                    .cadenceGlass(in: Capsule(), fallback: .thinMaterial)
                    .accessibilityIdentifier("session.healthSaved")
            }
        }
        .keepAwake(!isManualLog)
        .task(id: refreshSignature) {
            let recent = (try? WorkoutRepository.recentSessions(context, limit: 21)) ?? [] // 20-session rep window + this one
            generalRepLadders = SessionRenderModel.generalRepLadders(recentSessions: recent,
                                                                     excluding: session)
            plannedExerciseIndex = indexedPlannedExercises()
            refreshLiveVolume()
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
        .sheet(item: $suggestExerciseRequest) { request in
            SuggestExerciseView(request: request,
                                exerciseForName: { name in
                                    plannedExerciseIndex[name] ?? exerciseForName(named: name)
                                },
                                onAdd: addSuggestedExercise)
        }
        .sheet(item: $swapTarget) { target in
            let pickAction: ExercisePickerView.PickAction = {
                switch target {
                // A logged exercise has a known source, so restore the similarity
                // ranked swap surface instead of falling through to plain search.
                case .logged: return .swap
                case .planned: return .swap
                }
            }()
            ExercisePickerView(action: pickAction, source: {
                switch target {
                case .logged(let exerciseID): return exerciseForID(exerciseID)
                case .planned(let oldName): return plannedExerciseIndex[oldName]
                }
            }()) { picked in
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
        .sheet(isPresented: $workoutSettingsPresented, onDismiss: {
            settings.lastStrengthSettings = workoutSettings
        }) {
            WorkoutSettingsSheet(
                warmupMinutes: $workoutSettings.warmupMinutes,
                cooldownMinutes: $workoutSettings.cooldownMinutes,
                restSeconds: $workoutSettings.restSeconds,
                autoStartRest: $workoutSettings.autoStartRest,
                preWorkoutCountdown: $workoutSettings.preWorkoutCountdown,
                autoEndOnIdle: $workoutSettings.autoEndOnIdle,
                idleTimeoutMinutes: $workoutSettings.idleTimeoutMinutes,
                plateRounding: $workoutSettings.plateRounding,
                useHR: $workoutSettings.useHRMonitoring)
        }
        .alert("Couldn't suggest an exercise", isPresented: $suggestExerciseFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Exercise data could not be read. Try again after the catalog finishes loading.")
        }
        .sheet(item: $setEditorRoute) { _ in
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
            if isActiveSession {
                sampleHR()
                active.writeHeartbeat()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { recordActivity() }
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
        .confirmationDialog("Remove this exercise?", isPresented: exerciseRemovalPresented,
                           titleVisibility: .visible) {
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

    func compactSummary(for ctx: SessionRenderModel.ExerciseContext) -> String {
        SessionRenderModel.compactSummary(context: ctx, unit: settings.unit)
    }
}
