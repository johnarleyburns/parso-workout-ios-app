import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures
/// Home dashboard.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(ActiveWorkoutModel.self) private var active
    @Environment(ContributionCoordinator.self) private var contributions
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \CardioWorkout.start, order: .reverse) private var cardio: [CardioWorkout]
    @Query(sort: \Assessment.date, order: .reverse) private var assessments: [Assessment]
    @Query(sort: \ReadinessEntry.date, order: .reverse) private var readinessEntries: [ReadinessEntry]
    @Query(filter: #Predicate<Exercise> { $0.isFavorite }, sort: \Exercise.name) private var favoriteExercises: [Exercise]

    @State private var logPickerPresented = false
    @State private var selectWorkoutPresented = false
    @State private var path = NavigationPath()
    @State private var cardioType: CardioType?
    @State private var outdoorType: CardioType?
    @State private var otherCardioTitle: String?
    @State private var intervalType: WorkoutType?
    @State private var intervalLaunch: IntervalLaunch?
    @State private var swimPresented = false
    @State private var pending: PendingWorkout?
    @State private var hrGateKind: PendingWorkout.Kind?
    @State private var startWarmupAfterHRGate = false
    @State private var warmupActive = false
    @State private var today: DayActivity?
    @State private var activityTrend: [DayActivity] = []
    @State private var passiveSamples: [PassiveReadinessSample] = []
    @State private var historyRefreshToken = UUID()
    @State private var timerCardioSetup: TimerCardioSetup?
    @State private var pendingPlan: EditablePlan?
    @State private var captureHR = false
    @State private var cardioPickerPresented = false
    @State private var weightsStartPresented = false
    @State private var cardioGoalFor: CardioType?
    @State private var warnAddOn: (session: CoachSession, status: CoachAddOnStatus)?
    @State private var outdoorGoalMeters: Double?
    @State private var showAlternatives = false
    @State private var showSupport = false
    @State private var pendingAddGapsDeficits: [BodyPart: Double]?
    @State private var suggestionsExpanded = false
    @State private var expandedTodayRowIDs: Set<String> = []
    @State private var weeklyVolumeExpanded = false
    @State private var coachIllustration = HomeCoachIllustration.random()
    @State private var showWorkoutConflict = false
    @State private var confirmCancelPrevious = false
    @State private var coachSnapshot: HomeCoachSnapshot = .placeholder
    private var dashboard: HomeDashboardState {
        let snapshot = CoachSnapshot(facts: coachSnapshot.facts, coachFacts: coachSnapshot.coachFacts,
                                     insights: coachSnapshot.insights, recommendation: coachSnapshot.recommendation,
                                     decision: coachSnapshot.decision, plan: coachSnapshot.plan,
                                     behindPlan: coachSnapshot.behindPlan, addOn: coachSnapshot.addOn,
                                     readiness: coachSnapshot.readiness, optimizedPlan: coachSnapshot.optimizedPlan)
        return HomeDashboardPresenter.make(snapshot: snapshot, schedule: settings.coachSchedulePreferences,
                                    goal: settings.trainingGoal, experience: settings.experienceLevel,
                                    userAge: settings.userAge)
    }
    private var coachFacts: TrainingFacts { coachSnapshot.facts }
    private var coachInsights: [Insight] { coachSnapshot.insights }
    private var coachRecommendation: Recommendation { coachSnapshot.recommendation }
    private var coachDecision: CoachDecision { coachSnapshot.decision }
    private var coachPlan: WeeklyPlan { coachSnapshot.plan }
    private var passiveReadinessDisplay: PassiveReadinessPresenter.Display? {
        PassiveReadinessPresenter.display(for: coachSnapshot.readiness)
    }
    @State private var testCardOverride: TestRecommendation?
    @State private var testCardDismissed = false
    private var testRecommendation: TestRecommendation? {
        if testCardDismissed { return nil }
        if let override = testCardOverride { return override }
        return HomeCoachModel.testRecommendation(
            coachHidden: settings.coachHidden,
            assessments: assessments,
            lastRecommendedAt: settings.lastTestRecommendationAt,
            snoozedUntil: settings.testRecommendationSnoozes)
    }
    /// Gates coach recomputation. Deliberately keyed on coarse history counts + the
    /// refresh token + coach-relevant settings — NOT per-set session churn — so
    /// logging a set never re-runs the pipeline. The token is bumped when a workout
    /// completes (and on log / ingest / delete / day-change); counts catch
    /// create/delete; settings catch preference edits. The signature type + rule
    /// now live in `HomeCoachModel` where they are unit-tested.
    private var coachSignature: HomeCoachModel.Signature {
        HomeCoachModel.signature(
            token: historyRefreshToken,
            sessions: sessions,
            cardio: cardio,
            assessments: assessments,
            readiness: readinessEntries,
            goal: settings.trainingGoal,
            experience: settings.experienceLevel,
            formula: settings.formula,
            schedule: settings.coachSchedulePreferences,
            profile: settings.coachPreferenceProfile,
            userAge: settings.userAge,
            overrideWeekKey: settings.coachPlanOverrideWeekKey)
    }
    private func buildCoachSnapshot() async -> HomeCoachSnapshot {
        let policy: PlanningConstraintPolicy = settings.isPlanOverrideActive() ? .meetDeficits : .safe
        let snapshot = HomeCoachSnapshot(await HomeCoachModel.snapshotAsync(
            sessions: sessions,
            cardio: cardio,
            assessments: assessments,
            readiness: readinessEntries,
            goal: settings.trainingGoal,
            experience: settings.experienceLevel,
            formula: settings.formula,
            schedule: settings.coachSchedulePreferences,
            profile: settings.coachPreferenceProfile,
            passiveSamples: passiveSamples,
            userAge: settings.userAge,
            constraintPolicy: policy))
        model.updateWatchTodayPlan(WatchSync.TodayPlan.from(day: snapshot.plan.today))
        return snapshot
    }
    private func handleInsightAction(_ action: Insight.Action) {
        switch action {
        case .addGapsToPlan(let deficits):
            pendingAddGapsDeficits = deficits
        case .revertToSafePlan:
            settings.coachPlanOverrideWeekKey = nil
            Haptics.selection()
        }
    }
    private func confirmAddGaps() {
        Haptics.selection()
        settings.coachPlanOverrideWeekKey = AppSettings.weekKey(for: Date())
        pendingAddGapsDeficits = nil
    }

    @ViewBuilder
    private var testRecommendationCard: some View {
        if let rec = testRecommendation {
            CoachTestRecommendationCard(
                recommendation: rec,
                onStart: { kind in
                    settings.lastTestRecommendationAt = Date()
                    testCardDismissed = true
                    path.append(HomeRoute.runAssessment(kind))
                },
                onPickDifferent: { pickDifferentTest() },
                onSnooze: { kind in snoozeTest(kind) })
        }
    }
    private func pickDifferentTest() {
        let summaries = AssessmentMath.summaries(from: assessments)
        let inputs = CoachTestRecommendationEngine.Inputs(
            summaries: summaries,
            lastRecommendedAt: nil,   // ignore the weekly gate while cycling
            snoozedUntil: settings.testRecommendationSnoozes)
        let candidates = CoachTestRecommendationEngine.candidates(inputs)
        guard let current = testRecommendation else {
            testCardOverride = candidates.first
            return
        }
        if let idx = candidates.firstIndex(where: { $0.kind == current.kind }),
           idx + 1 < candidates.count {
            testCardOverride = candidates[idx + 1]
        } else {
            testCardOverride = candidates.first { $0.kind != current.kind } ?? current
        }
    }

    private func snoozeTest(_ kind: AssessmentKind) {
        let until = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        var snoozes = settings.testRecommendationSnoozes
        snoozes[kind.rawValue] = until
        settings.testRecommendationSnoozes = snoozes
        settings.lastTestRecommendationAt = Date()
        testCardOverride = nil
        testCardDismissed = true
    }
    private var addOnRecommendation: CoachAddOnRecommendation { coachSnapshot.addOn }
    private static let headerDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return f
    }()
    private var headerDateText: String { Self.headerDateFormatter.string(from: .now) }
    /// Phase A (field-test-fixes): resume card from either in-memory active session
    /// or a persisted `isResumable` candidate the coach pipeline detects but
    /// ActiveWorkoutModel hasn't yet adopted.
    private var resumeSession: WorkoutSession? {
        active.strengthSession ?? ActiveSessionRecovery.candidate(in: sessions)
    }

    private var todayStrength: (hasStrength: Bool, exerciseNames: [String]) { TodayLogHelper.completedStrength(sessions: sessions) }
    private var weeklyVolumeKg: Double {
        WeeklyStats.volumeKg(
            sessions.filter { $0.deletedAt == nil },
            since: WeeklyStats.weekStart())
    }
    var body: some View {
        ZStack {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(headerDateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("home.headerDate")

                    if let s = resumeSession { resumeCard(s) }
                    homeActionRow
                    HomeWorkoutsTodaySection(
                        rows: workoutsTodayRows,
                        expandedRowIDs: $expandedTodayRowIDs,
                        onOpenCompleted: openTodayWorkout,
                        onStartPlanned: startPlannedToday)
                    HomeWeekDashboardSection(
                        dashboard: dashboard,
                        volumeExpanded: $weeklyVolumeExpanded,
                        strengthEntries: weekActivity.strength,
                        cardioEntries: weekActivity.cardio,
                        totalVolumeKg: weeklyVolumeKg,
                        unit: settings.unit,
                        onOpenWorkout: openWeekWorkout)
                    HomeCoachSuggestionsSection(
                        suggestions: dashboard.suggestions,
                        recommendation: previewableCoachRecommendation,
                        illustration: coachIllustration,
                        expanded: $suggestionsExpanded,
                        onStartRecommendation: {
                            if let recommendation = previewableCoachRecommendation {
                                launchDecision(recommendation)
                            }
                        })
                }
                .padding()
            }
            .background { CadenceGlassBackdrop(tint: .green) }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
                case .coach:
                    // Observations are free and continuous for everyone; only the
                    // prescription behind them is Pro. Free users still get the
                    // full, live insights list here.
                    CoachInsightsView(insights: coachInsights,
                                      onFixCustomExercises: { path.append(HomeRoute.customExercises) },
                                      onInsightAction: { handleInsightAction($0) })
                case .coachPreferences: CoachSchedulePreferencesView()
                case .yourPlan:
                    let facts = coachSnapshot.coachFacts.withStepSummary(from: activityTrend)
                    let plan = HomePlanPresenter.yourPlanDestinationPlan(cachedPlan: coachSnapshot.plan)
                    YourWeekView(decision: coachDecision, facts: facts,
                                 trainingFacts: coachSnapshot.facts,
                                 optimizedPlan: coachSnapshot.optimizedPlan,
                                 plan: plan,
                                 sessions: sessions.filter { $0.deletedAt == nil },
                                 cardio: cardio.filter { $0.deletedAt == nil },
                                 path: $path)
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
                today = await model.health.todayActivity()
                activityTrend = await model.health.activityTrend(days: 7)
                passiveSamples = await model.health.passiveReadinessSamples(days: 60)
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
            .sheet(isPresented: $selectWorkoutPresented) {
                SelectWorkoutView(
                    recommendation: coachRecommendation,
                    coachSession: coachStrengthSession,
                    onQuickStart: {
                        selectWorkoutPresented = false
                        startQuickStartStrength()
                    },
                    onEditorStart: { plan in selectWorkoutPresented = false; handleEditorStart(plan) },
                    onSelect: { type in selectWorkoutPresented = false; start(type) },
                    onOtherCardio: { description, gps in
                        selectWorkoutPresented = false
                        startOtherCardio(description: description, gps: gps)
                    })
            }
            .sheet(item: $cardioType, onDismiss: releaseCardioWorkout) { RecordCardioView(initialType: $0, customTitle: otherCardioTitle, captureHR: captureHR, onSaved: { _ in workoutSaved(); releaseCardioWorkout() }) }
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
            .sheet(isPresented: $cardioPickerPresented) {
                WorkoutTypePicker(onSelect: { cardioPickerPresented = false; start($0) },
                                  onEditorStart: { _ in },
                                  onOtherCardio: { desc, gps in cardioPickerPresented = false; startOtherCardio(description: desc, gps: gps) },
                                  types: [.run, .walk, .cycle, .swim, .hiit, .boxing, .other],
                                  title: "Start Cardio")
            }
            // Volume tile (batch 8) → strength start (Quick Start / Warm-Up / Reuse / presets).
            .sheet(isPresented: $weightsStartPresented) {
                NavigationStack {
                    WeightsStartView(
                        onEditorStart: { plan in weightsStartPresented = false; handleEditorStart(plan) },
                        recommendation: coachRecommendation,
                        coachSession: coachStrengthSession)
                }
            }
            // Optional distance goal before a run/walk/cycle (batch 8).
            .sheet(item: $cardioGoalFor) { type in
                CardioGoalSheet(type: type) { goal in
                    outdoorGoalMeters = goal
                    cardioGoalFor = nil
                    begin(.outdoor(type))
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
            PreWorkoutHRView(workoutType: kind.cardioType) { source in
                hrGateKind = nil
                captureHR = source != .none
                proceedFromHRGate(kind, useHR: source != .none)
            }
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
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            let today = Self.dayString()
            if settings.lastCoachComputeDay != today {
                settings.lastCoachComputeDay = today
                historyRefreshToken = UUID()
            }
            if contributionPromptAllowed { contributions.evaluate() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutHistoryChanged)) { _ in
            // A past workout's date was edited (SessionView). The coach signature
            // keys on counts + token, not per-session dates, so bump the token to
            // recompute the snapshot / "This Week" strip without an app relaunch.
            markWorkoutHistoryChanged()
        }
        .onChange(of: active.finishedSummary != nil) { _, shown in
            if shown {
                ContributionCoordinator.recordWorkoutCompleted()
                // A strength workout just finished — refresh the (decoupled) coach
                // snapshot so Home reflects it when the user returns.
                markWorkoutHistoryChanged()
            }
        }
        // Recompute the coach pipeline OFF the render/tap path, only when history or
        // coach-relevant settings actually change (see `coachSignature`). This keeps
        // set logging instant — the pipeline no longer runs on every set save.
        .task(id: coachSignature) {
            coachSnapshot = await buildCoachSnapshot()
        }
        // Passive HealthKit samples arrive asynchronously after the initial pipeline
        // run; rebuild the snapshot once they land (and whenever they change).
        .onChange(of: passiveSamples) {
            Task { coachSnapshot = await buildCoachSnapshot() }
        }
        .coachOverrideConfirmation(
            pending: $pendingAddGapsDeficits,
            guardrails: { CoachOverrideGuardrails.describe(from: coachSnapshot.optimizedPlan.diagnostics) },
            onConfirm: { confirmAddGaps() })
    }

    /// The contribution toast is allowed only on Home with no workout (or workout
    /// start sequence) in progress, so it never interrupts training.
    private var contributionPromptAllowed: Bool {
        active.strengthSession == nil && hrGateKind == nil && pending == nil && !warmupActive
    }

    private static func dayString(_ date: Date = Date()) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }

    /// Invalidates the history-derived surfaces after a save/log/ingest/delete.
    /// Yields one main-actor turn first so the SwiftData change has propagated to
    /// the `@Query` arrays before SwiftUI re-enters the computed Coach/week paths.
    private func markWorkoutHistoryChanged() {
        Task { @MainActor in
            await Task.yield()
            historyRefreshToken = UUID()
        }
    }

    /// A genuine, user-completed workout (cardio/interval/swim/logged) was saved:
    /// refresh history AND count it toward the optional contribution prompt.
    /// HealthKit ingest (`syncCardioFromHealth`) intentionally does NOT count;
    /// strength completion is counted separately via `active.finishedSummary`.
    private func workoutSaved() {
        markWorkoutHistoryChanged()
        ContributionCoordinator.recordWorkoutCompleted()
    }
    /// Pulls any new Watch/Health-recorded cardio into the local store (FR-2.1).
    /// Formerly auto-run by the now-removed Cardio screen (feedback batch 3).
    private func syncCardioFromHealth() async {
        let new = await model.health.newWorkouts(since: model.lastHealthSync)
        let inserted = (try? WorkoutRepository.ingest(new, in: context)) ?? 0
        model.lastHealthSync = Date()
        if inserted > 0 { markWorkoutHistoryChanged() }
    }
    private var homeActionRow: some View {
        VStack(spacing: CGFloat(LayoutMetrics.actionButtonSpacing)) {
            CadenceActionButton(title: "Start Workout", systemImage: "play.fill") {
                Haptics.selection()
                if active.liveWorkout.active != nil { showWorkoutConflict = true } else { selectWorkoutPresented = true }
            }
            .accessibilityIdentifier("home.startWorkout")
            CadenceActionButton(title: "Log Previous Workout",
                                systemImage: "square.and.pencil",
                                emphasis: .secondary) {
                Haptics.selection()
                logPickerPresented = true
            }
            .accessibilityIdentifier("home.logWorkout")
        }
    }
    /// Today's completed workouts plus the coach plan still outstanding.
    /// Ordering, badge vocabulary and planned volume live in the presenter.
    private var workoutsTodayRows: [WorkoutsTodayPresenter.Row] {
        WorkoutsTodayPresenter.rows(
            sessions: sessions,
            cardio: cardio,
            plannedToday: coachDecision.todayPlannedRecommendations)
    }
    private func openTodayWorkout(_ row: WorkoutsTodayPresenter.Row) {
        guard let id = UUID(uuidString: row.sourceKey) else { return }
        switch row.modality {
        case .strength:
            if let s = sessions.first(where: { $0.id == id }) { path.append(s) }
        case .cardio:
            if let c = cardio.first(where: { $0.id == id }) { path.append(c) }
        }
    }
    private func startPlannedToday(_ row: WorkoutsTodayPresenter.Row) {
        guard let session = coachDecision.todayPlannedRecommendations
            .first(where: { $0.id == row.sourceKey }) else { return }
        Haptics.selection()
        launchDecision(session)
    }
    private var previewableCoachRecommendation: CoachSession? {
        switch coachDecision.primary.launchPayload {
        case .strengthPlan, .cardio:
            return coachDecision.primary
        case .recovery, .rest, .assessment:
            return nil
        }
    }

    private var coachStrengthSession: CoachSession? {
        guard let session = previewableCoachRecommendation, session.kind == .strength else { return nil }
        return session
    }

    /// Quiet trial status shown above the Coach card while on the free trial.
    private func trialBanner(daysLeft: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "gift.fill").font(.caption)
            Text("Trial — \(daysLeft) day\(daysLeft == 1 ? "" : "s") left")
                .font(.caption.weight(.medium))
            Spacer()
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.green.opacity(0.10), in: Capsule())
        .accessibilityIdentifier("coach.trialBanner")
    }

    private var weekStripSection: some View {
        _ = historyRefreshToken
        return WeekStripView(
            plan: coachPlan,
            balance: coachDecision.weeklyBalance,
            preferences: settings.coachSchedulePreferences,
            onTap: {
                Haptics.selection()
                switch HomePlanPresenter.weekStripTapRoute() {
                case .yourPlan:
                    path.append(HomeRoute.yourPlan)
                }
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.weekStrip")
    }

    private var homeFavoriteRoutines: [WorkoutPlan] {
        settings.favoriteRoutineIDs.compactMap { PlanCatalog.plan(forKey: $0) }
            .sorted { $0.name < $1.name }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        let routines = homeFavoriteRoutines
        if !routines.isEmpty || !favoriteExercises.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Favorites", systemImage: "heart.fill")
                    .font(.headline).foregroundStyle(.pink)
                if !routines.isEmpty {
                    Text("Routines").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(routines) { plan in
                        NavigationLink {
                            RoutineDetailView(plan: plan, onEditorStart: { plan in handleEditorStart(plan); path = NavigationPath() })
                        } label: {
                            HStack {
                                Text(plan.name).font(.subheadline)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !favoriteExercises.isEmpty {
                    Text("Exercises").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.top, routines.isEmpty ? 0 : 4)
                    ForEach(favoriteExercises) { ex in
                        NavigationLink {
                            ExerciseDetailView(exercise: ex)
                        } label: {
                            HStack {
                                Text(ex.name).font(.subheadline)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cadenceGlassCard(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: .pink)
        }
    }

    private var weekActivity: (strength: [TodayActivityPresenter.Entry], cardio: [TodayActivityPresenter.Entry]) {
        _ = historyRefreshToken
        return TodayActivityPresenter.weekEntries(sessions: sessions, cardio: cardio)
    }
    private func openWeekWorkout(_ entry: TodayActivityPresenter.Entry) {
        switch entry.kind {
        case .strength:
            if let s = sessions.first(where: { $0.id == entry.sourceId }) { path.append(s) }
        case .cardio:
            if let c = cardio.first(where: { $0.id == entry.sourceId }) { path.append(c) }
        }
    }
    private func resumeCard(_ session: WorkoutSession) -> some View {
        Button {
            Haptics.selection()
            if active.strengthSession == nil {
                let heartbeat = WorkoutHeartbeatStore.read()
                active.adopt(session, heartbeat: heartbeat)
            }
            active.present()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resume \(session.title.isEmpty ? "Workout" : session.title)").font(.headline)
                    Text("\(session.orderedSets.count) sets logged").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading)
            .cadenceGlassBackground(
                in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                tint: .green,
                interactive: true,
                fallback: AnyShapeStyle(.green.opacity(0.18)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier("home.resume")
    }
    private func start(_ type: WorkoutType) {
        // Only "Other Cardio" carries a custom title; clear any stale one first.
        otherCardioTitle = nil
        if type.isStrength {
            // Weights is handled inside the sheet (WeightsStartView), so this
            // branch is normally unreached.
            launchFromPicker(.strength)
        } else if type == .swim {
            guard acquireCardio(.swim(id: UUID())) else { return }
            swimPresented = true
        } else if type.usesGPS, let c = type.cardioType {
            startOutdoorWithGoal(c)
        } else if type == .hiit || type == .boxing {
            intervalType = type
        } else if let c = type.cardioType {
            begin(.timer(c))
        }
    }
    private func startQuickStartStrength() {
        guard active.liveWorkout.active == nil else {
            showWorkoutConflict = true
            return
        }
        pendingPlan = nil
        startWarmupAfterHRGate = false
        if settings.warmupMinutes > 0 {
            warmupActive = true
        } else {
            launch(.strength, startCue: .single)
        }
    }
    /// "Other Cardio" chosen (feedback batch 6 item 3): stash its description, then
    /// route to the GPS recorder or the indoor timer per the user's GPS toggle.
    private func startOtherCardio(description: String, gps: Bool) {
        outdoorGoalMeters = nil   // Other Cardio carries no distance goal.
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        otherCardioTitle = trimmed.isEmpty ? nil : trimmed
        begin(gps ? .outdoor(.other) : .timer(.other))
    }

    /// Presents the optional distance-goal chooser before a run/walk/cycle (batch 8).
    /// A fresh start clears any prior goal; the chooser sets it (or leaves it nil).
    private func startOutdoorWithGoal(_ type: CardioType) {
        otherCardioTitle = nil
        outdoorGoalMeters = nil
        cardioGoalFor = type
    }

    /// Launches a strength/plan workout chosen from the Start sheet without a Home
    /// flash (P1 #1/#5). Strength workouts route through the HR gate first, then
    /// the get-ready countdown.
    /// `skipCountdown` makes "Quick Start" truly immediate — no countdown
    /// regardless of the Settings value (which still applies to library/reuse/warm-up).
    private func launchFromPicker(_ kind: PendingWorkout.Kind, skipCountdown: Bool = false) {
        if skipCountdown {
            launch(kind)
        } else {
            proceedFromHRGate(kind, useHR: false)
        }
    }
    private func begin(_ kind: PendingWorkout.Kind) {
        hrGateKind = kind
    }

    /// Called after the HR gate closes.  If the countdown is enabled, show it;
    /// otherwise launch immediately.
    private func proceedFromHRGate(_ kind: PendingWorkout.Kind, useHR: Bool) {
        if startWarmupAfterHRGate {
            startWarmupAfterHRGate = false
            warmupActive = true
            return
        }
        if case .interval = kind {
            launch(kind)
            return
        }
        if kind.isStrength || settings.preWorkoutCountdown > 0 {
            pending = PendingWorkout(kind: kind)
        } else {
            launch(kind)
        }
    }
    private func launch(_ kind: PendingWorkout.Kind, startCue: WorkoutStartCue = .countdown) {
        guard active.liveWorkout.active == nil else { showWorkoutConflict = true; return }
        switch kind {
        case .strength:
            if let plan = pendingPlan {
                pendingPlan = nil
                startStrengthAfterLease(startCue: startCue) { try? materializePlan(plan) }
            } else { startStrengthAfterLease(startCue: startCue) { try? WorkoutRepository.createSession(title: "Workout", in: context) } }
        case .plan(let plan, let ladder):
            startStrengthAfterLease(startCue: startCue) { try? WorkoutRepository.startSession(from: plan, repLadder: ladder, in: context) }
        case .reuse(let past):
            startStrengthAfterLease(startCue: startCue) { try? WorkoutRepository.reuseSession(from: past, in: context) }
        case .outdoor(let c):
            guard acquireCardio(.outdoorCardio(id: UUID(), type: c)) else { return }
            outdoorType = c
        case .interval(let l):
            guard acquireCardio(.interval(id: UUID(), type: l.saveType)) else { return }
            intervalLaunch = l
        case .timer(let c):
            guard acquireCardio(.timerCardio(id: UUID(), type: c)) else { return }
            cardioType = c
        }
    }

    private func startStrengthAfterLease(startCue: WorkoutStartCue,
                                         create: () -> WorkoutSession?) {
        let intent = LiveWorkoutStartIntent(kind: .strength(sessionID: UUID()),
                                             routePayload: "strength",
                                             origin: .finalCommit)
        guard case .granted(let lease) = active.liveWorkout.requestStart(intent: intent,
                                                                            descriptorName: "Workout") else {
            showWorkoutConflict = true
            return
        }
        guard let session = create(), active.startStrength(session, lease: lease) else {
            _ = active.liveWorkout.release(lease)
            return
        }
        playStartCue(startCue)
    }

    private func acquireCardio(_ kind: LiveWorkoutKind) -> Bool {
        guard active.liveWorkout.active == nil else { showWorkoutConflict = true; return false }
        let name: String
        switch kind {
        case .outdoorCardio(_, let type), .timerCardio(_, let type), .interval(_, let type): name = type.displayName
        case .swim: name = "Swim"
        case .strength: name = "Workout"
        }
        let intent = LiveWorkoutStartIntent(kind: kind, routePayload: kindName(kind), origin: .homeStart)
        guard case .granted = active.liveWorkout.requestStart(intent: intent, descriptorName: name) else {
            showWorkoutConflict = true
            return false
        }
        return true
    }

    private func kindName(_ kind: LiveWorkoutKind) -> String {
        switch kind {
        case .outdoorCardio(_, let type), .timerCardio(_, let type), .interval(_, let type): return type.rawValue
        case .swim: return "swim"
        case .strength: return "strength"
        }
    }

    private func releaseCardioWorkout() {
        guard active.strengthSession == nil else { return }
        if let lease = active.liveWorkout.lease { _ = active.liveWorkout.release(lease) }
    }

    private func finishWarmup(elapsedSeconds secs: Int, startCue: WorkoutStartCue) {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) {
            launch(.strength, startCue: startCue)
            // Record the actual warm-up time on the session just created
            // (feedback batch 6).
            active.strengthSession?.warmupSeconds = Double(secs)
            try? context.save()
            warmupActive = false
        }
    }

    private func playStartCue(_ cue: WorkoutStartCue) {
        switch cue {
        case .countdown:
            WorkoutCues.startBeepSequence(enabled: settings.workoutSounds)
        case .single:
            WorkoutCues.singleStart(enabled: settings.workoutSounds)
        case .none:
            break
        }
    }

    /// Handles an add-on selection from the post-completion coach card. Encouraged
    /// and neutral options launch directly; warn options show a confirmation dialog.
    private func handleAddOn(_ session: CoachSession, _ status: CoachAddOnStatus) {
        switch CoachRouter.addOnAction(status: status) {
        case .launch:
            launchDecision(session)
        case .warn:
            warnAddOn = (session, status)
        }
    }

    /// Launch from the CoachDecision engine. Every trainable recommendation lands
    /// on that workout's setup/settings surface first — never directly into an
    /// active recorder (audio/coach routing plan §D). The recorder begins only
    /// after the user confirms from the setup screen. The pure routing decision
    /// lives in `CoachRouter` (unit-tested); this only performs the UI action.
    private func launchDecision(_ session: CoachSession) {
        switch CoachRouter.destination(for: session) {
        case .planEditor(let plan):
            path.append(HomeRoute.workoutEditor(plan))
        case .emptyEditor(let title):
            // Defensive: a strength session with no exercises should never dead-end
            // back to Home (issue 3). Open an empty editor titled from the session.
            let fallback = EditablePlan(
                title: title,
                warmupMinutes: settings.warmupMinutes,
                cooldownMinutes: settings.cooldownMinutes,
                exercises: [])
            path.append(HomeRoute.workoutEditor(fallback))
        case .outdoorCardio(let type):
            startOutdoorWithGoal(type)             // → CardioGoalSheet → HR gate → recorder
        case .swim:
            swimPresented = true                   // SwimRecordView opens to its setup screen
        case .interval(let workoutType):
            intervalType = workoutType             // → IntervalSetupView (protocol picker)
        case .timerCardio(let type, let suggestedMinutes):
            timerCardioSetup = TimerCardioSetup(type: type, suggestedMinutes: suggestedMinutes)
        case .none:
            break
        }
    }

    /// User picked a different cardio modality from the alternatives chooser.
    /// Records the preference so Coach learns, dismisses the sheet, then launches
    /// the chosen session on the next runloop turn — deferring the launch lets the
    /// alternatives sheet finish dismissing before the cardio setup sheet/cover
    /// presents (SwiftUI drops a present that races an in-flight dismiss).
    private func chooseAlternative(_ session: CoachSession) {
        let decision = coachDecision
        settings.recordCoachSelection(session, alternatives: [decision.primary] + decision.alternatives)
        showAlternatives = false
        Task { @MainActor in
            await Task.yield()
            launchDecision(session)
        }
    }

    /// "Something else?" from the alternatives sheet → the full cardio picker,
    /// after the sheet finishes dismissing (same one-runloop deferral).
    private func openFullCardioPicker() {
        showAlternatives = false
        Task { @MainActor in
            await Task.yield()
            cardioPickerPresented = true
        }
    }

    /// "Do a strength workout anyway" (coach-user-control Phase 5): build the
    /// best-fit full-body session and open it in the plan editor for perusal.
    private func strengthAnyway() {
        let facts = coachSnapshot.coachFacts.withStepSummary(from: activityTrend)
        guard let plan = EditablePlan.strengthAnyway(
            facts: facts,
            desiredSetsPerExercise: settings.coachSchedulePreferences.desiredSetsPerExercise
        ) else { return }
        path.append(HomeRoute.workoutEditor(plan))
    }

    /// Swap one component of a two-a-day plan: strength → the strength start
    /// surface (Coach's Workout / presets / reuse); cardio → the full picker.
    private func swapComponent(_ session: CoachSession) {
        if session.kind == .strength { weightsStartPresented = true }
        else { cardioPickerPresented = true }
    }

    private func handleEditorStart(_ plan: EditablePlan) {
        pendingPlan = plan
        if plan.warmupMinutes > 0 {
            startWarmupAfterHRGate = true
        }
        proceedFromHRGate(.strength, useHR: false)
    }

    private func materializePlan(_ plan: EditablePlan) throws -> WorkoutSession {
        let session = try WorkoutRepository.createSession(title: plan.title, in: context)
        plan.apply(to: session)
        for name in plan.exercises.map(\.name) {
            _ = try WorkoutRepository.findOrCreateExercise(named: name, in: context)
        }
        session.cooldownSeconds = Double(plan.cooldownMinutes * 60)
        try context.save()
        return session
    }
}
