import SwiftUI
import SwiftData
import UIKit
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
                RestTimerBar(model: rest,
                             onComplete: {
                                 Haptics.restComplete()
                                 UIAccessibility.post(notification: .announcement,
                                                      argument: String(localized: "Rest complete. Ready for the next set."))
                             },
                             onChange: { syncRestAlarm(to: $0) })
            }
            if let plan { planBanner(plan) }
            partnerBar
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
            ForEach(cache.state.contexts, id: \.exerciseID) { ctx in
                exerciseCardView(for: ctx)
                    .id(ctx.exerciseID)
            }
            ForEach(plannedOnlyNames, id: \.self) { name in
                plannedCard(name)
            }
            VStack(alignment: .leading, spacing: 16) {
                CadenceActionButton(title: String(localized: "Add Exercise"),
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
                        confirmMessage: String(localized: "This finishes and saves your workout.")
                    )
                } else if isManualLog {
                    CadenceActionButton(title: String(localized: "Done"), systemImage: "checkmark") {
                        finishManualLog()
                    }
                    .accessibilityIdentifier("log.done")
                }
            }
            .padding(.top, 8)
        }
        .padding(CGFloat(LayoutMetrics.pagePadding))
        .accessibilityRotor("Exercises", entries: cache.state.contexts, entryID: \.exerciseID, entryLabel: \.name)
        .accessibilityRotor("Unlogged sets", entries: pendingRotorEntries, entryID: \.id, entryLabel: \.label)
        .sensoryFeedback(.success, trigger: setLoggedRevision)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: setLoggedRevision)
    }

    private var sessionSurfaceBase: some View {
        sessionScrollSurface
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            if isActiveSession {
                VStack(spacing: 0) {
                    WorkoutElapsedHeader(clock: active.clock, isPaused: active.isPaused, timers: $timers)
                    SessionLiveHRBand()
                }
            }
        }
        .toolbar { toolbarContent }
        .overlay { sessionTopOverlay }
        .overlay(alignment: .bottom) {
            quickTalkOverlay
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
        .onChange(of: settings.raiseToTalk) { _, enabled in
            handleRaiseToTalkSettingChange(enabled)
        }
        .onChange(of: raiseToTalkMonitor.isRaised) { _, raised in
            handleRaiseToTalkChange(raised)
        }
        .sheet(isPresented: $pickerPresented) {
            ExercisePickerView(onPick: handleExercisePickerSelection)
        }
        .sheet(isPresented: $voiceLoggingPresented) {
            VoiceLoggingSheet(
                currentExercise: cache.state.contexts.first(where: { !$0.pendingSets.isEmpty })
                    .flatMap { exerciseForID($0.exerciseID) }?.name,
                exercises: session.exercisesInOrder.map(\.name),
                performers: roster.map(\.name),
                activePerformer: voicePerformerWasProvided
                    ? (voicePerformerID.flatMap(people(for:))?.name ?? "Me") : nil,
                unit: settings.unit,
                bodyweight: cache.state.contexts.first(where: { !$0.pendingSets.isEmpty })
                    .flatMap { exerciseForID($0.exerciseID) }.map(isBodyweight) ?? false,
                smarterVoiceUnderstanding: settings.smarterVoiceUnderstanding,
                initialPhrase: quickTalkTranscript,
                onAction: applyVoiceAction)
        }
        .sheet(item: $suggestExerciseRequest, content: suggestedExerciseSheet)
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
        .sheet(item: $setEditorRoute) { _ in inlineSetEditorSheetContent }
        .fullScreenCover(isPresented: $coolingDown, content: cooldownOverlay)
        .modifier(SessionCooldownConfirmationModifier(isPresented: $coolDownConfirm,
                                                       onStart: startCooldown))
        .task { _ = try? WorkoutRepository.me(in: context) }
        .onAppear(perform: startWatchIfNeeded)
        .modifier(QuickTalkNotificationModifier(isActive: isActiveSession,
                                                 isEnabled: settings.voiceLoggingEnabled,
                                                 isPresented: $voiceLoggingPresented))
        .onReceive(NotificationCenter.default.publisher(for: .cadenceLiveActivityActionRequested), perform: handleLiveActivityRequest)
        .onDisappear(perform: handleSessionDisappear)
        // Keep the Date publisher closure explicit. Passing the method as a
        // `perform:` witness makes Swift 6.3 emit an oversized reabstraction
        // thunk for this view's generic modifier chain.
        .onReceive(idleTimer) { date in
            handleIdleTimer(date)
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhaseChange(phase)
        }
        .modifier(SessionIdlePromptModifier(isPresented: $idlePromptShown,
                                             message: idlePromptMessage,
                                             onKeepGoing: recordActivity,
                                             onSave: endWorkout))
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
        .modifier(ExerciseRemovalConfirmationModifier(isPresented: exerciseRemovalPresented,
                                                       onRemove: removeExerciseFromConfirmation))
    }

    var body: some View {
        sessionPresentation
    }
}
