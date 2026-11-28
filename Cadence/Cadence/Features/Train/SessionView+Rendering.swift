import SwiftUI
import SwiftData
import UIKit
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures
extension SessionView {
    @ViewBuilder
    var scrollContent: some View {
        VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.sectionSpacing)) {
            if isManualLog { loggedDateBanner }
            if active.strengthSession?.id != session.id && !isManualLog {
                editableMetadataRow
            }
            if rest.isRunning {
                RestTimerBar(model: rest,
                             onComplete: {
                                 Haptics.restComplete()
                                 UIAccessibility.post(notification: .announcement,
                                                      argument: String(localized: "Rest complete. Ready for the next set."))
                             },
                             onChange: { syncRestAlarm(to: $0) })
            }
            if let plan { planBanner(plan) }
            if hasPartners { partnerDisclosure }
            if isEmptySession {
                CadenceActionButton(title: String(localized: "Use Previous Workout"),
                                    systemImage: "clock.arrow.circlepath",
                                    tint: .accentColor) {
                    usePreviousPresented = true
                }
                .accessibilityIdentifier("session.usePrevious")

                ContentUnavailableView("Empty workout",
                                       systemImage: "dumbbell",
                                       description: Text("Use a previous workout, or add exercises below."))
            }
            // Exercise rows are one continuous list: tight spacing between
            // them, with the page rhythm reserved for sections around it.
            VStack(alignment: .leading, spacing: 8) {
                ForEach(cache.state.contexts, id: \.exerciseID) { ctx in
                    exerciseCardView(for: ctx)
                        .id(ctx.exerciseID)
                }
                ForEach(plannedOnlyNames, id: \.self) { name in
                    plannedCard(name)
                }
            }
            VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.sectionSpacing)) {
                suggestExerciseButton

                if !isActiveSession && isManualLog {
                    CadenceActionButton(title: String(localized: "Done"), systemImage: "checkmark") {
                        finishManualLog()
                    }
                    .accessibilityIdentifier("log.done")
                }
            }
        }
        .padding(CGFloat(LayoutMetrics.pagePadding))
        .accessibilityRotor("Exercises", entries: cache.state.contexts, entryID: \.exerciseID, entryLabel: \.name)
        .accessibilityRotor("Unlogged sets", entries: pendingRotorEntries, entryID: \.id, entryLabel: \.label)
        .sensoryFeedback(.success, trigger: setLoggedRevision)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: setLoggedRevision)
    }

    private var sessionSurfaceBase: some View {
        sessionScrollSurface
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isActiveSession {
                WorkoutControlBar(
                    isPaused: active.isPaused,
                    onPauseToggle: togglePause,
                    onEnd: endWorkout,
                    // "Cool down, then finish" starts the cooldown immediately;
                    // a second confirmation dialog here was redundant.
                    onCoolDown: startCooldownAfterDialog,
                    confirmMessage: String(localized: "This finishes and saves your workout.")
                )
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            if isActiveSession {
                WorkoutElapsedHeader(clock: active.clock, isPaused: active.isPaused, timers: $timers,
                                     trailing: AnyView(SessionLiveHRInline()))
            }
        }
        .toolbar { toolbarContent }
        .overlay { sessionTopOverlay }
        .overlay(alignment: .bottom) {
            if isActiveSession && !settings.hasSeenFirstSetCoachMark &&
               session.orderedSets.isEmpty && !cache.state.contexts.isEmpty {
                FirstSetCoachMark {
                    settings.hasSeenFirstSetCoachMark = true
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(3)
            }
        }
        .keepAwake(!isManualLog)
    }

    private var sessionPresentation: some View {
        sessionSurfaceBase
        .task(id: refreshSignature, refreshSession)
        .onAppear(perform: handleSessionAppear)
        .onDisappear(perform: handleSessionDisappear)
        .sheet(isPresented: $pickerPresented) {
            ExercisePickerView(onPick: handleExercisePickerSelection)
        }
        .sheet(item: $suggestExerciseRequest, content: suggestedExerciseSheet)
        .sheet(isPresented: $volumeSummaryPresented) {
            NavigationStack {
                ScrollView {
                    LiveWorkoutVolumeSummary(state: liveVolumeState,
                                             expanded: .constant(true),
                                             performers: liveVolumePerformers,
                                             performerStates: liveVolumePerformerStates)
                        .padding(CGFloat(LayoutMetrics.pagePadding))
                }
                .navigationTitle("Volume Summary")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { volumeSummaryPresented = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $detailExercise) { exercise in
            NavigationStack {
                ExerciseDetailView(exercise: exercise)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { detailExercise = nil }
                        }
                    }
            }
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
        .modifier(SuggestionFailureAlertModifier(isPresented: $suggestExerciseFailed))
        .sheet(item: $setEditorRoute, onDismiss: closeInlineEditor) { _ in inlineSetEditorSheetContent }
        .fullScreenCover(isPresented: $coolingDown, content: cooldownOverlay)
        .task { _ = try? WorkoutRepository.me(in: context) }
        .onAppear(perform: startWatchIfNeeded)
        .onAppear { timers.startRestIfNeeded(now: Date()) }
        .onReceive(NotificationCenter.default.publisher(for: .cadenceLiveActivityActionRequested), perform: handleLiveActivityRequest)
        .onDisappear(perform: handleSessionDisappear)
        // Keep the Date publisher closure explicit. Passing the method as a
        // `perform:` witness makes Swift 6.3 emit an oversized reabstraction
        // thunk for this view's generic modifier chain.
        .onReceive(idleTimer) { date in
            handleIdleTimer(date)
        }
        .alert("Rename workout", isPresented: $renamePresented) {
            TextField("Title", text: $editedTitle).accessibilityIdentifier("rename.field")
            Button("Save") {
                session.title = editedTitle.trimmingCharacters(in: .whitespaces)
                try? context.save()
            }
            Button("Cancel", role: .cancel) { }
        }
        .modifier(SessionDeleteConfirmationModifier(isPresented: $showDeleteConfirm,
                                                     onDelete: deleteSessionFromConfirmation))
        .sheet(isPresented: $datePickerPresented, content: sessionDatePickerSheet)
        .sheet(isPresented: $endDatePickerPresented, content: sessionEndDatePickerSheet)
        .confirmationDialog("Heart Rate", isPresented: $showHRInfo, titleVisibility: .visible) {
            Button("Reconnect Apple Watch HR") { model.reconnectWatchHR() }
                .accessibilityIdentifier("session.watch.reconnect")
            Button("Done", role: .cancel) {}
        } message: {
            Text(model.watchHRStatusText)
        }
        .modifier(ExerciseRemovalConfirmationModifier(isPresented: exerciseRemovalPresented,
                                                       onRemove: removeExerciseFromConfirmation))
    }

    var body: some View {
        sessionPresentation
    }
}
