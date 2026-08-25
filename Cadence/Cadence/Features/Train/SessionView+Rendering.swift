import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension SessionView {
    @ViewBuilder
    var scrollContent: some View {
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
            ExercisePickerView(action: pickAction, source: {
                switch target {
                case .logged(let exerciseID): return exerciseForID(exerciseID)
                case .planned(let oldName): return session.exercisesInOrder.first { $0.name == oldName }
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
    func exerciseCardView(for ctx: SessionRenderModel.ExerciseContext) -> some View {
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

    func compactSummary(for ctx: SessionRenderModel.ExerciseContext) -> String {
        SessionRenderModel.compactSummary(context: ctx, unit: settings.unit)
    }
}
