import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension HomeView {
    var dashboardContent: some View {
        AnyView(ZStack {
            dashboardNavigation
            dashboardTransientOverlays
        })
    }

    private var dashboardNavigation: some View {
        AnyView(
            homeNavigationDestinations(
                usesExternalNavigation
                    ? AnyView(dashboardScrollContent)
                    : AnyView(NavigationStack(path: pathBinding) {
                        dashboardScrollContent
                    }))
            .task {
                // HealthKit queries are asynchronous, but the old launch chain
                // started the heaviest reads immediately. Keep each query
                // cancellable and yield between them, publish one coherent
                // update, and leave a short settling window before importing
                // Watch workouts into SwiftData. This keeps the first
                // interactive frames free without sending the main-actor
                // HealthDataProviding value across a concurrent task.
                let loadedToday = await model.health.todayActivity()
                guard !Task.isCancelled else { return }
                await Task.yield()
                let loadedTrend = await model.health.activityTrend(days: 7)
                guard !Task.isCancelled else { return }
                await Task.yield()
                let loadedReadiness = await model.health.passiveReadinessSamples(days: 60)
                guard !Task.isCancelled else { return }
                today = loadedToday
                activityTrend = loadedTrend
                passiveSamples = loadedReadiness

                try? await Task.sleep(for: .milliseconds(750))
                guard !Task.isCancelled else { return }
                await syncCardioFromHealth()
            }
            .refreshable {
                today = await model.health.todayActivity()
                activityTrend = await model.health.activityTrend(days: 7)
                passiveSamples = await model.health.passiveReadinessSamples(days: 60)
                await syncCardioFromHealth()
            }
            .sheet(isPresented: $logPickerPresented) {
                LogWorkoutPicker(onSaved: workoutSaved)
            }
            .sheet(isPresented: $readinessPresented) {
                ReadinessCheckInView(existing: todayReadiness)
            }
            .sheet(isPresented: $selectWorkoutPresented, onDismiss: presentPendingSuggestedWorkout) {
                SelectWorkoutView(
                    onQuickStart: {
                        selectWorkoutPresented = false
                        startQuickStartStrength()
                    },
                    onSuggestedWorkout: { requestSuggestedWorkout($0) },
                    onEditorStart: { plan in selectWorkoutPresented = false; handleEditorStart(plan) },
                    onSelect: { type in selectWorkoutPresented = false; start(type) },
                    onOtherCardio: { description, gps in
                        selectWorkoutPresented = false
                        startOtherCardio(description: description, gps: gps)
                    },
                    recentCardioTypes: recentCardioTypes)
            }
            .sheet(item: $cardioType, onDismiss: releaseCardioWorkout) {
                RecordCardioView(initialType: $0, tracksGPS: cardioTracksGPS,
                                 customTitle: otherCardioTitle, captureHR: captureHR,
                                 onSaved: { _ in workoutSaved(); releaseCardioWorkout() })
            }
            .fullScreenCover(item: $outdoorType, onDismiss: releaseCardioWorkout) { OutdoorCardioView(type: $0, customTitle: otherCardioTitle, goalMeters: outdoorGoalMeters, captureHR: captureHR, onSaved: { _ in workoutSaved(); releaseCardioWorkout() }) }
            .sheet(item: $timerCardioSetup, onDismiss: releaseCardioWorkout) { setup in
                TimerCardioSetupView(type: setup.type, suggestedMinutes: setup.suggestedMinutes,
                                     onSaved: { _ in workoutSaved(); releaseCardioWorkout() })
            }
            .sheet(isPresented: $showAlternatives) {
                NavigationStack {
                    CoachAlternativesView(decision: coachDecision,
                                          onSelect: { chooseAlternative($0) },
                                          onOpenCardioPicker: { openFullCardioPicker() })
                }
            }
            // Contribution prompt — Home only, never during a workout or its
            // start sequence (decision: don't interfere with a workout).
            .overlay(alignment: .bottom) {
                if contributions.showToast, contributionPromptAllowed {
                    ContributionToast(
                        onSupport: { contributions.dismissToast(); showSupport = true },
                        onLater:   { contributions.dismissToast() },
                        onNever:   { contributions.optOutForever() })
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: contributions.showToast)
            .sheet(isPresented: $showSupport) {
                NavigationStack {
                    ContributionSupportView(store: contributions.store, showsDoneButton: true)
                }
            }
            .alert("Workout already in progress", isPresented: $showWorkoutConflict) {
                if active.strengthSession != nil {
                    Button("Resume") { active.present(); showWorkoutConflict = false }
                        .accessibilityIdentifier("workoutConflict.resume")
                    Button("Cancel Previous Workout…", role: .destructive) {
                        showWorkoutConflict = false
                        confirmCancelPrevious = true
                    }
                    .accessibilityIdentifier("workoutConflict.cancelPrevious")
                } else {
                    Button("Keep Current Workout") { showWorkoutConflict = false }
                        .accessibilityIdentifier("workoutConflict.keepCurrent")
                }
                Button("Not Now", role: .cancel) { showWorkoutConflict = false }
                    .accessibilityIdentifier("workoutConflict.notNow")
            } message: {
                Text(active.liveWorkout.active.map { descriptor in
                    let sets = active.strengthSession?.orderedSets.count ?? 0
                    return "\(descriptor.name) is active\(sets > 0 ? " with \(sets) logged sets" : ""). Resume it or cancel it before starting another workout."
                } ?? "Finish or discard the current workout before starting another.")
            }
            .alert("Discard this workout?", isPresented: $confirmCancelPrevious) {
                Button("Discard Workout", role: .destructive) {
                    guard let session = active.strengthSession else { return }
                    session.deletedAt = Date()
                    try? context.save()
                    active.discardActive()
                    selectWorkoutPresented = true
                }
                .accessibilityIdentifier("workoutConflict.confirmCancel")
                Button("Keep Workout", role: .cancel) { }
            } message: {
                Text("This removes the in-progress workout and its \(active.strengthSession?.orderedSets.count ?? 0) logged sets from your active workout. The record is kept in history and can be restored there.")
            }
            // Cardio-min tile (batch 8) → the Start picker filtered to cardio types.
            .sheet(isPresented: $cardioPickerPresented, onDismiss: presentPendingSuggestedWorkout) {
                WorkoutTypePicker(onSelect: { cardioPickerPresented = false; start($0) },
                                  onEditorStart: { _ in },
                                  onOtherCardio: { desc, gps in cardioPickerPresented = false; startOtherCardio(description: desc, gps: gps) },
                                  onSuggestedWorkout: { requestSuggestedWorkout($0) },
                                  types: [.run, .walk, .cycle, .rowing, .swim, .elliptical, .stairClimber, .hiit, .boxing, .other],
                                  title: "Start Cardio")
            }
            // Volume tile (batch 8) → strength start (Quick Start / Warm-Up / Reuse / presets).
            .sheet(isPresented: $weightsStartPresented, onDismiss: presentPendingSuggestedWorkout) {
                NavigationStack {
                    WeightsStartView(
                        onEditorStart: { plan in weightsStartPresented = false; handleEditorStart(plan) },
                        onSuggestedWorkout: { requestSuggestedWorkout($0) })
                }
            }
            .overlay {
                if suggestedWorkoutCalculating || suggestedCardioCalculating {
                    ProgressView(suggestedCardioCalculating
                                 ? "Building your cardio workout…"
                                 : "Building your strength workout…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("suggestedWorkout.calculating")
                }
            }
            .alert("Couldn’t calculate your Personalized workout", isPresented: suggestedWorkoutFailurePresented) {
                Button("Try Again") { suggestedWorkoutFailure = nil; requestSuggestedWorkout(.strength) }
                Button("Cancel", role: .cancel) { suggestedWorkoutFailure = nil }
            } message: {
                Text(suggestedWorkoutFailure ?? "")
            }
            .alert("Couldn’t calculate your cardio workout", isPresented: Binding(
                get: { suggestedCardioFailure != nil },
                set: { if !$0 { suggestedCardioFailure = nil } })) {
                Button("Try Again") {
                    suggestedCardioFailure = nil
                    requestSuggestedWorkout(.cardio)
                }
                Button("Cancel", role: .cancel) { suggestedCardioFailure = nil }
            } message: {
                Text(suggestedCardioFailure ?? "")
            }
            .sheet(item: $suggestedCardio) { suggestion in
                NavigationStack {
                    SuggestedCardioPreviewView(suggestion: suggestion) { selected in
                        suggestedCardio = nil
                        Task { @MainActor in
                            await Task.yield()
                            launchSuggestedCardio(selected)
                        }
                    }
                }
            }
            .alert("Couldn't open this workout", isPresented: Binding(
                get: { routeFailure != nil },
                set: { if !$0 { routeFailure = nil } })) {
                Button("Try Again") {
                    if let failure = routeFailure { retryRouteFailure(failure) }
                }
                Button("Close", role: .cancel) { routeFailure = nil }
            } message: {
                Text(routeFailure?.message ?? "")
            }
            // Optional distance goal before a run/walk/cycle (batch 8).
            .sheet(item: $cardioGoalFor) { type in
                CardioGoalSheet(type: type) { goal, indoors in
                    outdoorGoalMeters = goal
                    cardioGoalFor = nil
                    cardioTracksGPS = indoors ? false : nil
                    begin(indoors ? .timer(type) : .outdoor(type))
                }
            }
            .sheet(item: $intervalType) { wType in
                IntervalSetupView(type: wType) { plan in
                    intervalType = nil
                    let useHR = settings.useHRMonitoring
                    let launch = IntervalLaunch(plan: plan, saveType: wType.cardioType ?? .hiit, captureHR: useHR)
                    if useHR {
                        // Let the shared gate offer either Bluetooth or Apple
                        // Watch for HIIT/boxing as well as continuous cardio.
                        begin(.interval(launch))
                    } else {
                        intervalLaunch = launch
                    }
                }
            }
            .fullScreenCover(item: $intervalLaunch, onDismiss: releaseCardioWorkout) { IntervalView(plan: $0.plan, saveType: $0.saveType, captureHR: $0.captureHR, onSaved: { _ in workoutSaved(); releaseCardioWorkout() }) }
            .fullScreenCover(isPresented: $swimPresented, onDismiss: releaseCardioWorkout) { SwimRecordView(onSaved: { _ in workoutSaved(); releaseCardioWorkout() }) }
            .confirmationDialog(
                "This is more load than planned today.",
                isPresented: Binding(
                    get: { warnAddOn != nil },
                    set: { if !$0 { warnAddOn = nil } }
                ),
                presenting: warnAddOn
            ) { item in
                Button("Start anyway") {
                    let session = item.session
                    warnAddOn = nil
                    launchDecision(session)
                }
                Button("Choose easier option", role: .cancel) {
                    warnAddOn = nil
                }
            } message: { _ in
                Text("Recovery may be the limiting factor. You can continue, but keep it easy if performance drops.")
            }
        )
    }

    private var dashboardScrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if surface == .today {
                    dashboardTopContent
                    dashboardBottomContent
                } else {
                    thisWeekContent
                }
            }
            .padding()
        }
        .background { CadenceGlassBackdrop(tint: .green) }
        .navigationTitle(surface.title)
    }

    private var thisWeekContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            dashboardWeekContent
            HomeMyHistorySection(
                entries: homeWeekHistoryEntries,
                onOpen: openWeekWorkout,
                onShowMore: { path.append(HomeRoute.history) })
        }
    }

    @ViewBuilder
    private var dashboardTransientOverlays: some View {
        // HR gate — appears before the get-ready countdown so the user can
        // connect HR, see live data, then press Start Workout.
        if let kind = hrGateKind {
            PreWorkoutHRView(
                workoutType: kind.cardioType,
                onContinue: { source in
                    hrGateKind = nil
                    captureHR = source != .none
                    proceedFromHRGate(kind, useHR: source != .none)
                },
                onCancel: { hrGateKind = nil })
                .transition(.identity)
                .zIndex(2)
        }
        if let p = pending {
            PreWorkoutCountdownView(
                seconds: settings.preWorkoutCountdown,
                onStart: {
                    let k = p.kind
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) { launch(k); pending = nil }
                },
                onCancel: { pending = nil })
                .transition(.identity)
                .zIndex(1)
        }
        if warmupActive {
            GuidedPhaseOverlay(
                title: "Warm Up",
                minutes: pendingPlan?.warmupMinutes ?? settings.warmupMinutes,
                tint: .orange,
                idPrefix: "warmup",
                soundsEnabled: settings.workoutSounds,
                onFinish: { secs in finishWarmup(elapsedSeconds: secs, startCue: .countdown) },
                onSkip: { secs in
                    WorkoutCues.cancelPendingSounds()
                    finishWarmup(elapsedSeconds: secs, startCue: .single)
                })
                .transition(.identity)
                .zIndex(1)
        }
    }

    @ViewBuilder
    private var dashboardTopContent: some View {
        HStack {
            Text(headerDateText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("home.headerDate")
            Spacer(minLength: 8)
            if contributions.store.isSupporter {
                Label("Supporter", systemImage: "heart.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.pink)
                    .accessibilityIdentifier("home.supporterBadge")
            }
        }
        if let s = resumeSession { resumeCard(s) }
        homeActionRow
        HomeMyWorkoutsSection(
            completed: workoutsTodayRows,
            scheduled: scheduledWorkouts,
            plannedItems: cachedScheduledItems,
            onOpenCompleted: openTodayWorkout,
            onStartScheduled: startScheduledWorkout,
            onShowMorePlanned: { path.append(HomeRoute.plannedWorkouts) })
    }

    private var dashboardWeekContent: some View {
        HomeWeekDashboardSection(
            dashboard: dashboard,
            strengthExpanded: $weeklyStrengthExpanded,
            cardioExpanded: $weeklyCardioExpanded,
            volumeExpanded: $weeklyVolumeExpanded,
            strengthEntries: weekActivity.strength,
            cardioEntries: weekActivity.cardio,
            muscleHistory: cachedMuscleHistory,
            totalVolumeKg: weeklyVolumeKg,
            unit: settings.unit,
            onOpenWorkout: openWeekWorkout,
            onOpenCoachSettings: { path.append(HomeRoute.coachPreferences) })
    }

    @ViewBuilder
    private var dashboardBottomContent: some View {
        homeDetailDisclosure(
            title: "Observations",
            subtitle: dashboard.suggestions.isEmpty ? "No new suggestions" : "Coach guidance and rationale",
            expanded: $observationsExpanded,
            identifier: "home.observations.show")
        if observationsExpanded {
            HomeCoachSuggestionsSection(
                suggestions: dashboard.suggestions,
                illustration: coachIllustration,
                expanded: $suggestionsExpanded)
        }
        homeDetailDisclosure(
            title: homeReadinessTitle,
            subtitle: homeReadinessSubtitle,
            expanded: $readinessExpanded,
            identifier: "home.readiness.show")
        if readinessExpanded { readinessCard }
    }

}
