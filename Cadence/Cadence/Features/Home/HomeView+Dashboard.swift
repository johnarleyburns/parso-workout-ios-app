import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension HomeView {
    var dashboardContent: some View {
        ZStack {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(headerDateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("home.headerDate")

                    if model.healthSyncStatus.isInProgress {
                        Label(model.healthSyncStatus.detailText,
                              systemImage: "heart.text.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("home.healthSync.status")
                    }

                    if model.coachRefreshInProgress {
                        Label("Updating coaching guidance…", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("home.coachCompute.status")
                    }

                    if let s = resumeSession { resumeCard(s) }
                    homeActionRow
                    HomeWorkoutsTodaySection(
                        rows: workoutsTodayRows,
                        onOpenCompleted: openTodayWorkout,
                        onShowMoreHistory: { path.append(HomeRoute.history) })
                    HomePlannedWorkoutsSection(
                        records: scheduledWorkouts,
                        onOpenAll: { path.append(HomeRoute.plannedWorkouts) },
                        onStart: startScheduledWorkout)
                    HomeWeekDashboardSection(
                        dashboard: dashboard,
                        volumeExpanded: $weeklyVolumeExpanded,
                        strengthEntries: weekActivity.strength,
                        cardioEntries: weekActivity.cardio,
                        totalVolumeKg: weeklyVolumeKg,
                        unit: settings.unit, onOpenWorkout: openWeekWorkout,
                        onOpenCoachSettings: { path.append(HomeRoute.coachPreferences) })
                    HomeCoachSuggestionsSection(
                        suggestions: dashboard.suggestions,
                        illustration: coachIllustration,
                        expanded: $suggestionsExpanded)
                    readinessCard
                }
                .padding()
            }
            .background { CadenceGlassBackdrop(tint: .green) }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if contributions.store.isSupporter {
                        Label("Supporter", systemImage: "heart.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.pink)
                            .accessibilityIdentifier("home.supporterBadge")
                    }
                    Button { Haptics.selection(); path.append(HomeRoute.settings) } label: {
                        Image(systemName: "gearshape")
                            .imageScale(.large)
                            .frame(width: 44, height: 44, alignment: .center)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("home.settings").accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: WorkoutSession.self) { SessionView(session: $0) }
            .navigationDestination(for: CardioWorkout.self) { CardioDetailView(workout: $0) }
            .navigationDestination(for: HistorySummaryRoute.self) { route in
                switch route {
                case .strength(let s):
                    WorkoutSummaryView(data: .from(session: s), onEdit: { path.append(s) })
                case .strengthFocused(let s, let id):
                    SessionView(session: s, initiallyExpandedExerciseID: id)
                case .cardio(let c):
                    CardioDetailView(workout: c)
                }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .settings: SettingsView()
                case .history: HistoryView(path: $path)
                case .plannedWorkouts: PlannedWorkoutsListView()
                case .coach:
                    // Observations and editable coaching guidance are available to
                    // every user; any plan mutation still requires explicit apply.
                    CoachInsightsView(insights: coachInsights,
                                      onFixCustomExercises: { path.append(HomeRoute.customExercises) },
                                      onInsightAction: { handleInsightAction($0) })
                case .coachPreferences: CoachSchedulePreferencesView()
                case .workoutEditor(let plan):
                    WorkoutPlanEditor(plan: plan, onStart: { plan in
                        handleEditorStart(plan)
                        path = NavigationPath()
                    })
                case .customExercises:
                    CustomExerciseListView()
                case .runAssessment(let kind):
                    AssessmentDetailView(kind: kind)
                }
            }
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
                    onSuggestedWorkout: { requestSuggestedWorkout() },
                    onEditorStart: { plan in selectWorkoutPresented = false; handleEditorStart(plan) },
                    onSelect: { type in selectWorkoutPresented = false; start(type) },
                    onOtherCardio: { description, gps in
                        selectWorkoutPresented = false
                        startOtherCardio(description: description, gps: gps)
                    })
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
                                  onSuggestedWorkout: { requestSuggestedWorkout() },
                                  types: [.run, .walk, .cycle, .rowing, .swim, .hiit, .boxing, .other],
                                  title: "Start Cardio")
            }
            // Volume tile (batch 8) → strength start (Quick Start / Warm-Up / Reuse / presets).
            .sheet(isPresented: $weightsStartPresented, onDismiss: presentPendingSuggestedWorkout) {
                NavigationStack {
                    WeightsStartView(
                        onEditorStart: { plan in weightsStartPresented = false; handleEditorStart(plan) },
                        onSuggestedWorkout: { requestSuggestedWorkout() })
                }
            }
            .overlay {
                if suggestedWorkoutCalculating {
                    ProgressView("Building your Personalized workout…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("suggestedWorkout.calculating")
                }
            }
            .alert("Couldn’t calculate your Personalized workout", isPresented: Binding(
                get: { suggestedWorkoutFailure != nil },
                set: { if !$0 { suggestedWorkoutFailure = nil } })) {
                Button("Try Again") { suggestedWorkoutFailure = nil; requestSuggestedWorkout() }
                Button("Cancel", role: .cancel) { suggestedWorkoutFailure = nil }
            } message: {
                Text(suggestedWorkoutFailure ?? "")
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
        }

        // Get-ready countdown as a plain opaque overlay above the whole
        // NavigationStack — not a fullScreenCover (P1 #5 follow-up). As a sibling
        // view (not a modal) it can appear in the same frame the Start sheet
        // dismisses, so Home never shows between the two. On finish we push the
        // session and drop the overlay in one animation-disabled transaction, so the
        // session is already on screen when the overlay vanishes — no Home flash
        // before the warm-up, and none after it.
        // HR gate — appears BEFORE the get-ready countdown.  Lets the
        // user connect HR, see live data, then press "Start Workout".
        if let kind = hrGateKind {
            PreWorkoutHRView(
                workoutType: kind.cardioType,
                onContinue: { source in
                    hrGateKind = nil
                    captureHR = source != .none
                    proceedFromHRGate(kind, useHR: source != .none)
                },
                onCancel: { hrGateKind = nil }
            )
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

        // "Start with Warm-Up" (feedback batch 4): a guided warm-up runs above the
        // stack, then opens a blank strength session (same no-flash transaction).
        if warmupActive {
            GuidedPhaseOverlay(
                title: "Warm Up",
                minutes: pendingPlan?.warmupMinutes ?? settings.warmupMinutes,
                tint: .orange,
                idPrefix: "warmup",
                soundsEnabled: settings.workoutSounds,
                onFinish: { secs in
                    finishWarmup(elapsedSeconds: secs, startCue: .countdown)
                },
                onSkip: { secs in
                    WorkoutCues.cancelPendingSounds()
                    finishWarmup(elapsedSeconds: secs, startCue: .single)
                })
                .transition(.identity)
                .zIndex(1)
        }
        }
    }
}
