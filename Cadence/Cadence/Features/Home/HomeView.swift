import SwiftUI
import SwiftData
import CadenceCore

/// Home dashboard (field-test round 3): a simple step count + workouts-this-week,
/// the Start Workout hero, and trends / cardio history / workout history surfaced
/// directly — not hidden under menus. A get-ready countdown runs before a workout.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(ActiveWorkoutModel.self) private var active
    @Environment(ContributionCoordinator.self) private var contributions
    @Environment(StoreService.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \CardioWorkout.start, order: .reverse) private var cardio: [CardioWorkout]
    @Query(sort: \Assessment.date, order: .reverse) private var assessments: [Assessment]
    @Query(sort: \ReadinessEntry.date, order: .reverse) private var readinessEntries: [ReadinessEntry]
    @Query(filter: #Predicate<Exercise> { $0.isFavorite }, sort: \Exercise.name) private var favoriteExercises: [Exercise]

    @State private var logPickerPresented = false
    @State private var path = NavigationPath()
    @State private var cardioType: CardioType?
    @State private var outdoorType: CardioType?
    /// Free-text label for an in-flight "Other Cardio" recording (feedback batch 6).
    @State private var otherCardioTitle: String?
    @State private var intervalType: WorkoutType?
    @State private var intervalLaunch: IntervalLaunch?
    @State private var swimPresented = false
    @State private var pending: PendingWorkout?
    /// Strength HR gate — shown BEFORE the get-ready countdown so the user can
    /// connect a strap or start the Watch, see live HR, then press Start.
    @State private var hrGateKind: PendingWorkout.Kind?
    /// When true, the warm-up overlay appears after the HR gate passes.
    @State private var startWarmupAfterHRGate = false
    @State private var warmupActive = false
    @State private var today: DayActivity?
    @State private var activityTrend: [DayActivity] = []
    /// Bumped after any workout-history mutation (save, log, ingest, delete) so the
    /// computed Coach / This Week / recent surfaces recompute immediately — without
    /// waiting for `scenePhase == .active` (the old "only fixed after re-entry" bug).
    @State private var historyRefreshToken = UUID()
    /// Setup surface for non-GPS timer cardio (rowing/other) launched from Coach.
    @State private var timerCardioSetup: TimerCardioSetup?
    @State private var pendingPlan: EditablePlan?
    @State private var captureHR = false
    // Quick-start shortcuts from the stat tiles (feedback batch 8).
    @State private var cardioPickerPresented = false
    @State private var weightsStartPresented = false
    @State private var cardioGoalFor: CardioType?
    @State private var warnAddOn: (session: CoachSession, status: CoachAddOnStatus)?
    @State private var outdoorGoalMeters: Double?
    @State private var showAlternatives = false
    @State private var showSupport = false
    @State private var showPaywall = false

    // Coach engine (strength-pivot P3/P5): one computed snapshot drives both the
    // read-only insights and the prescriptive recommendation surfaced on the card.
    private var coachFacts: TrainingFacts {
        TrainingFacts.make(sessions: sessions.filter { $0.deletedAt == nil },
                           assessments: assessments,
                           goal: settings.trainingGoal,
                           experience: settings.experienceLevel,
                           formula: settings.formula)
    }
    private var coachInsights: [Insight] {
        _ = historyRefreshToken
        let decision = baseCoachDecision
        let optimized = optimizedCoachPlan(for: decision)
        return PlanAwareInsightEngine.run(
            completed: coachFacts,
            plan: coachPlan,
            plannedStrengthSessions: optimized.plannedStrengthSessions,
            unresolvedDeficits: optimized.unresolvedDeficits,
            diagnostics: optimized.diagnostics,
            isBehindPlan: coachInsightsBehindPlan,
            now: Date())
    }
    /// The top prescription the Coach card leads with (P5.2). Never nil — the engine
    /// falls back to a cited cold-start starter when there's no history yet.
    private var coachRecommendation: Recommendation {
        let events = buildTrainingEvents()
        let facts = CoachFacts.make(from: events, goal: settings.trainingGoal,
                                     experience: settings.experienceLevel,
                                     formula: settings.formula)
        if let rec = CoachRecommendationEngine.run(facts, profile: settings.coachPreferenceProfile)
            .first(where: { rec in
                if let system = rec.system {
                    return [.maximalStrength, .hypertrophy, .strengthEndurance].contains(system)
                }
                return [.progression, .deload, .addVolume, .starter, .strengthBlock, .volumeAdjust].contains(rec.kind)
            }) {
            return rec
        }
        return RecommendationEngine.top(coachFacts)
    }

    private var baseCoachDecision: CoachDecision {
        _ = historyRefreshToken
        let events = buildTrainingEvents()
        let facts = CoachFacts.make(from: events, goal: settings.trainingGoal,
                                     experience: settings.experienceLevel,
                                     formula: settings.formula)
        let todayDate = Calendar.current.startOfDay(for: Date())
        let todayReadiness = readinessEntries.first { Calendar.current.startOfDay(for: $0.date) == todayDate }
        let hasPain = todayReadiness?.hasPainOrIllnessConcern ?? false
        return CoachDecisionEngine.run(facts,
                                         profile: settings.coachPreferenceProfile,
                                         schedulePreferences: settings.coachSchedulePreferences,
                                         hasPainConcern: hasPain)
    }

    private var coachDecision: CoachDecision {
        let decision = baseCoachDecision
        return decisionByApplyingOptimizedStrength(decision, optimizedPlan: optimizedCoachPlan(for: decision))
    }

    private var coachPlan: WeeklyPlan {
        let facts = CoachFacts.make(
            from: buildTrainingEvents(), goal: settings.trainingGoal,
            experience: settings.experienceLevel, formula: settings.formula)
        return WeeklyPlan.generate(from: facts, schedulePreferences: settings.coachSchedulePreferences)
    }

    private var coachInsightsBehindPlan: Bool {
        if case .offPlan = coachDecision.planAdherence { return true }
        return false
    }

    // MARK: Coach presence (coach-surface-design.md §2, as amended)

    /// The current Home coach surface. Insights are continuous; only the introducing
    /// card and the "Unlock the Coach" CTA are paced.
    private var coachSurfaceState: CoachSurfaceState {
        CoachSurfacePresenter.state(
            entitlement: store.entitlement,
            hidden: settings.coachHidden,
            introImpressions: settings.coachIntroImpressions,
            hasInsight: coachInsights.first != nil,
            protocolPackPending: !settings.lastSeenCoachKBVersion.isEmpty
                && CoachKBBadge.hasUnseenUpdate(lastSeen: settings.lastSeenCoachKBVersion))
    }

    private var coachShowsUnlockCTA: Bool {
        CoachUpsellPolicy.shouldShowCTA(isPro: false, lastShown: settings.lastCoachUpsellShown)
    }

    /// Top-of-Home coach surface: the functional card for entitled users, the full
    /// introducing pitch for new/updated free users, nothing otherwise (the ambient
    /// row lives below the user's own data).
    @ViewBuilder
    private var coachTopSurface: some View {
        switch coachSurfaceState {
        case .pro, .trial:
            VStack(alignment: .leading, spacing: 8) {
                if let days = store.trialDaysRemaining {
                    trialBanner(daysLeft: days)
                }
                CoachDecisionCardView(
                    decision: coachDecision,
                    addOnRecommendation: addOnRecommendation,
                    topInsight: coachInsights.first,
                    onStart: { launchDecision($0) },
                    onAddOn: { session, status in handleAddOn(session, status) },
                    onSeeInsights: { path.append(HomeRoute.coach) },
                    onPreferences: { path.append(HomeRoute.yourPlan) },
                    onPickAlternative: { showAlternatives = true })
            }
        case .introducing:
            CoachPreviewView(
                plan: coachPlan,
                topInsight: coachInsights.first,
                prescription: coachRecommendation,
                showUnlockCTA: coachShowsUnlockCTA,
                onUnlock: { showPaywall = true },
                onCTADisplayed: { settings.lastCoachUpsellShown = Date() })
                .onAppear { settings.coachIntroImpressions += 1 }
        case .ambient, .insight, .hidden:
            EmptyView()
        }
    }

    /// The compact ambient/insight coach row, placed after the user's own data.
    @ViewBuilder
    private var coachAmbientSurface: some View {
        if coachSurfaceState.showsCompactRow {
            CoachRow(
                topInsight: coachInsights.first,
                onTap: { path.append(HomeRoute.coachPreview) },
                onHide: { settings.coachHidden = true })
        }
    }

    private func optimizedCoachPlan(for decision: CoachDecision) -> OptimizedCoachPlan {
        let events = buildTrainingEvents()
        let facts = CoachFacts.make(from: events, goal: settings.trainingGoal,
                                    experience: settings.experienceLevel,
                                    formula: settings.formula)
        let plan = WeeklyPlan.generate(from: facts, schedulePreferences: settings.coachSchedulePreferences)
        let candidates = strengthOptimizationCandidates(for: decision, facts: facts)
        return CoachPlanOptimizer.optimize(
            trainingFacts: coachFacts,
            coachFacts: facts,
            weeklyPlan: plan,
            schedulePreferences: settings.coachSchedulePreferences,
            candidates: candidates)
    }

    private func strengthOptimizationCandidates(for decision: CoachDecision,
                                                facts: CoachFacts) -> [CoachSession] {
        let engineCandidates = CoachSession.candidates(for: facts,
                                                       schedulePreferences: settings.coachSchedulePreferences)
        var seen = Set<String>()
        return ([decision.primary] + decision.todayPlannedRecommendations + decision.alternatives + engineCandidates)
            .filter { session in
                guard session.kind == .strength, !((session.exercises ?? []).isEmpty) else { return false }
                return seen.insert(session.id).inserted
            }
    }

    private func decisionByApplyingOptimizedStrength(_ decision: CoachDecision,
                                                     optimizedPlan: OptimizedCoachPlan) -> CoachDecision {
        guard !optimizedPlan.plannedStrengthSessions.isEmpty else { return decision }

        var nextOptimized = optimizedPlan.plannedStrengthSessions.makeIterator()
        var optimizedToday: [CoachSession] = []
        for session in decision.todayPlannedRecommendations {
            if session.kind == .strength, let replacement = nextOptimized.next() {
                optimizedToday.append(replacement)
            } else {
                optimizedToday.append(session)
            }
        }

        var primary = decision.primary
        if primary.kind == .strength {
            primary = optimizedToday.first(where: { $0.kind == .strength })
                ?? optimizedPlan.plannedStrengthSessions.first
                ?? primary
        } else if optimizedToday.count == 1, let only = optimizedToday.first, only.kind == .strength {
            primary = only
        }

        let citationIds = Array(Set(decision.citationIds + primary.citationIds)).sorted()
        return CoachDecision(
            id: decision.id,
            generatedAt: decision.generatedAt,
            primary: primary,
            alternatives: decision.alternatives,
            deferred: decision.deferred,
            warnings: decision.warnings,
            observedFacts: decision.observedFacts,
            weeklyBalance: decision.weeklyBalance,
            confidence: decision.confidence,
            citationIds: citationIds,
            planAdherence: decision.planAdherence,
            todayCompletedMatches: decision.todayCompletedMatches,
            scoreBreakdowns: decision.scoreBreakdowns,
            todayPlannedRecommendations: optimizedToday)
    }

    private var addOnRecommendation: CoachAddOnRecommendation {
        guard case .planComplete = coachDecision.planAdherence else { return .empty }
        let events = buildTrainingEvents()
        let facts = CoachFacts.make(from: events, goal: settings.trainingGoal,
                                     experience: settings.experienceLevel,
                                     formula: settings.formula)
        let todayDate = Calendar.current.startOfDay(for: Date())
        let todayReadiness = readinessEntries.first { Calendar.current.startOfDay(for: $0.date) == todayDate }
        let hasPain = todayReadiness?.hasPainOrIllnessConcern ?? false
        return CoachAddOnEngine.run(facts: facts,
                                     schedulePreferences: settings.coachSchedulePreferences,
                                     hasPainConcern: hasPain)
    }

    private func buildTrainingEvents() -> [TrainingEvent] {
        _ = historyRefreshToken
        let activeSessions = sessions.filter { $0.deletedAt == nil }
        let strengthEvents = activeSessions.compactMap { TrainingEvent.from(session: $0, formula: settings.formula) }
        let cardioEvents = cardio.filter { $0.deletedAt == nil }.map { TrainingEvent.from(cardio: $0) }
        let assessmentEvents = assessments.map { TrainingEvent.from(assessment: $0) }
        return strengthEvents + cardioEvents + assessmentEvents
    }

    private static let headerDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return f
    }()
    private var headerDateText: String { Self.headerDateFormatter.string(from: .now) }

    var body: some View {
        @Bindable var active = active
        return ZStack {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(headerDateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("home.headerDate")

                    if let s = active.strengthSession { resumeCard(s) }
                    coachTopSurface
                    quickActionsRow
                    plannedRestOfWeekSection
                    coachAmbientSurface
                    favoritesSection
                    whatYouDidSection
                }
                .padding()
            }
            .background { CadenceGlassBackdrop(tint: .green) }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Haptics.selection(); path.append(HomeRoute.settings) } label: { Image(systemName: "gearshape") }
                        .accessibilityIdentifier("home.settings").accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: WorkoutSession.self) { SessionView(session: $0) }
            .navigationDestination(for: CardioWorkout.self) { CardioDetailView(workout: $0) }
            .navigationDestination(for: HistorySummaryRoute.self) { route in
                switch route {
                case .strength(let s):
                    WorkoutSummaryView(data: .from(session: s), onEdit: { path.append(s) })
                case .cardio(let c):
                    CardioDetailView(workout: c)
                }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .history: HistoryView(path: $path)
                case .settings: SettingsView()
                case .coach:
                    // Observations are free and continuous for everyone; only the
                    // prescription behind them is Pro. Free users still get the
                    // full, live insights list here.
                    CoachInsightsView(insights: coachInsights)
                case .coachPreview:
                    CoachPreviewScreen(
                        topInsight: coachInsights.first,
                        prescription: coachRecommendation,
                        showUnlockCTA: coachShowsUnlockCTA,
                        onUnlock: { showPaywall = true },
                        onCTADisplayed: { settings.lastCoachUpsellShown = Date() },
                        onHide: {
                            settings.coachHidden = true
                            if !path.isEmpty { path.removeLast() }
                        })
                case .coachPreferences: CoachSchedulePreferencesView()
                case .planning: PlanningView(switchToWorkout: { path = NavigationPath() },
                                             onOpenCoach: { path.append(HomeRoute.coachPreview) })
                case .yourPlan:
                    let facts = CoachFacts.make(
                        from: buildTrainingEvents(), goal: settings.trainingGoal,
                        experience: settings.experienceLevel, formula: settings.formula,
                        activityTrend: activityTrend)
                    YourWeekView(decision: coachDecision, facts: facts)
                case .workoutEditor(let plan):
                    WorkoutPlanEditor(plan: plan, onStart: { plan in
                        handleEditorStart(plan)
                        path = NavigationPath()
                    })
                }
            }
            .task {
                today = await model.health.todayActivity()
                activityTrend = await model.health.activityTrend(days: 7)
                await syncCardioFromHealth()
            }
            .refreshable {
                today = await model.health.todayActivity()
                activityTrend = await model.health.activityTrend(days: 7)
                await syncCardioFromHealth()
            }
            .sheet(isPresented: $logPickerPresented) {
                LogWorkoutPicker(onSaved: workoutSaved)
            }
            // P1 #9 — the post-workout summary is presented here, above the whole
            // NavigationStack, so the finished session can pop behind it.
            .fullScreenCover(item: $active.finishedSummary) { finished in
                WorkoutSummaryView(data: finished.data,
                                   onDone: { active.finishedSummary = nil })
            }
            .sheet(item: $cardioType) { RecordCardioView(initialType: $0, customTitle: otherCardioTitle, captureHR: captureHR, onSaved: { _ in workoutSaved() }) }
            .fullScreenCover(item: $outdoorType) { OutdoorCardioView(type: $0, customTitle: otherCardioTitle, goalMeters: outdoorGoalMeters, captureHR: captureHR, onSaved: { _ in workoutSaved() }) }
            .sheet(item: $timerCardioSetup) { setup in
                TimerCardioSetupView(type: setup.type, suggestedMinutes: setup.suggestedMinutes,
                                     onSaved: { _ in workoutSaved() })
            }
            .sheet(isPresented: $showAlternatives) {
                NavigationStack {
                    CoachAlternativesView(decision: coachDecision,
                                          onSelect: { chooseAlternative($0) })
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
            .sheet(isPresented: $showPaywall) {
                PaywallView()
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
                        recommendation: coachRecommendation)
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
                    // Intervals skip the numeric get-ready countdown: the pre-workout
                    // HR gate (inside IntervalView) + the protocol's own warm-up phase
                    // are the "get ready" (feedback batch 5).
                    intervalLaunch = IntervalLaunch(plan: plan, saveType: wType.cardioType ?? .hiit)
                }
            }
            .fullScreenCover(item: $intervalLaunch) { IntervalView(plan: $0.plan, saveType: $0.saveType, captureHR: captureHR, onSaved: { _ in workoutSaved() }) }
            .fullScreenCover(isPresented: $swimPresented) { SwimRecordView(onSaved: { _ in workoutSaved() }) }
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
            PreWorkoutHRView(workoutType: kind.cardioType) { useHR in
                hrGateKind = nil
                captureHR = useHR
                proceedFromHRGate(kind, useHR: useHR)
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
        .onChange(of: active.finishedSummary != nil) { _, shown in
            if shown { ContributionCoordinator.recordWorkoutCompleted() }
        }
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

    /// The four secondary entry points, demoted from full-width pills to one
    /// compact row (the primary action now lives inside the Coach card).
    private var quickActionsRow: some View {
        HStack(spacing: 10) {
            quickAction("Strength", "dumbbell.fill", id: "home.startWorkout") {
                weightsStartPresented = true
            }
            quickAction("Cardio", "figure.run", id: "home.startCardio") {
                cardioPickerPresented = true
            }
            quickAction("Log", "square.and.pencil", id: "home.logWorkout") {
                logPickerPresented = true
            }
            quickAction("Programs", "books.vertical", id: "home.planning") {
                path.append(HomeRoute.planning)
            }
        }
        .glassGroup(spacing: 10)
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

    private func quickAction(_ title: String, _ symbol: String, id: String,
                             action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button { Haptics.selection(); action() } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.vertical, 8)
            .foregroundStyle(.tint)
            .cadenceGlassBackground(in: shape, interactive: true, fallback: AnyShapeStyle(.background.secondary))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var restOfWeekDays: [WeeklyPlan.DayOutline] {
        _ = historyRefreshToken
        return coachPlan.remainingCalendarWeekDays.filter { !$0.sessions.isEmpty }
    }

    /// The near-term schedule is now on Home, so users do not have to open a
    /// second overview screen just to see what is coming next this week.
    /// When the rest of the current week is empty, shows planned next week instead.
    private var plannedRestOfWeekSection: some View {
        _ = historyRefreshToken
        let thisWeekDays = restOfWeekDays
        let nextWeekDays = coachPlan.nextWeekDays.filter { !$0.sessions.isEmpty }
        let showNextWeek = thisWeekDays.isEmpty && !nextWeekDays.isEmpty

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(showNextWeek ? "Planned (next week)" : "Planned (rest of week)").font(.headline)
                Spacer()
            }

            if thisWeekDays.isEmpty && nextWeekDays.isEmpty {
                Text("No more planned sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if showNextWeek {
                VStack(spacing: 0) {
                    ForEach(Array(nextWeekDays.prefix(7).enumerated()), id: \.element.id) { index, day in
                        if index > 0 { Divider().padding(.leading, 38) }
                        CoachPlanDayRow(day: day)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(thisWeekDays.enumerated()), id: \.element.id) { index, day in
                        if index > 0 { Divider().padding(.leading, 38) }
                        CoachPlanDayRow(day: day)
                    }
                }
            }

            Button { Haptics.selection(); path.append(HomeRoute.yourPlan) } label: {
                HStack(spacing: 4) {
                    Text("Your plan")
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.yourPlan")
        }
        .padding()
        .cadenceGlassCard(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: .green)
        .accessibilityIdentifier("home.plannedRestOfWeek")
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
            .cadenceGlassCard(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: .pink)
        }
    }

    // MARK: Inline sections (surfaced, not hidden)

    private var whatYouDidFacts: [ObservedFact] {
        _ = historyRefreshToken
        return coachDecision.observedFacts
            .filter { $0.kind == .lastStrength || $0.kind == .lastCardio }
            .sorted { ($0.occurredAt ?? .distantPast) > ($1.occurredAt ?? .distantPast) }
    }

    private var whatYouDidSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What you did").font(.headline)

            let facts = whatYouDidFacts
            if facts.isEmpty {
                Text("No recent training data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                        if index > 0 { Divider().padding(.leading, 40) }
                        whatYouDidFactRow(fact)
                    }
                }
            }

            Button { Haptics.selection(); path.append(HomeRoute.history) } label: {
                HStack(spacing: 4) {
                    Text("View more")
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.train")
        }
        .padding()
        .cadenceGlassCard(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: .teal)
        .accessibilityIdentifier("home.whatYouDid")
    }

    private func whatYouDidFactRow(_ fact: ObservedFact) -> some View {
        HStack(spacing: 8) {
            Image(systemName: fact.kind == .lastStrength ? "dumbbell.fill" : "heart.fill")
                .font(.caption)
                .foregroundStyle(fact.kind == .lastStrength ? .green : .teal)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(fact.title)
                    .font(.subheadline.weight(.medium))
                if let detail = fact.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(fact.value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.fact.\(fact.id)")
    }

    private func resumeCard(_ session: WorkoutSession) -> some View {
        Button { Haptics.selection(); path.append(session) } label: {
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

    // MARK: Routing (countdown gate)

    /// A type was chosen in the Start sheet. Strength launches via the push-behind
    /// path (handled inside the sheet); cardio dismisses the sheet first, then
    /// presents its own flow.
    private func start(_ type: WorkoutType) {
        // Only "Other Cardio" carries a custom title; clear any stale one first.
        otherCardioTitle = nil
        if type.isStrength {
            // Weights is handled inside the sheet (WeightsStartView), so this
            // branch is normally unreached.
            launchFromPicker(.strength)
        } else if type == .swim {
            swimPresented = true
        } else if type.usesGPS, let c = type.cardioType {
            startOutdoorWithGoal(c)
        } else if type == .hiit || type == .boxing {
            intervalType = type
        } else if let c = type.cardioType {
            begin(.timer(c))
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
        if kind.isStrength || settings.preWorkoutCountdown > 0 {
            pending = PendingWorkout(kind: kind)
        } else {
            launch(kind)
        }
    }
    private func launch(_ kind: PendingWorkout.Kind, startCue: WorkoutStartCue = .countdown) {
        switch kind {
        case .strength:
            if let plan = pendingPlan {
                pendingPlan = nil
                if let s = try? materializePlan(plan) {
                    active.startStrength(s); path.append(s)
                    playStartCue(startCue)
                }
            } else if let s = try? WorkoutRepository.createSession(title: "Workout", in: context) {
                active.startStrength(s); path.append(s)
                playStartCue(startCue)
            }
        case .plan(let plan, let ladder):
            if let s = try? WorkoutRepository.startSession(from: plan, repLadder: ladder, in: context) {
                active.startStrength(s); path.append(s)
                playStartCue(startCue)
            }
        case .reuse(let past):
            if let s = try? WorkoutRepository.reuseSession(from: past, in: context) {
                active.startStrength(s); path.append(s)
                playStartCue(startCue)
            }
        case .outdoor(let c): outdoorType = c
        case .interval(let l): intervalLaunch = l
        case .timer(let c): cardioType = c
        }
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
        switch status {
        case .encouraged, .neutral:
            launchDecision(session)
        case .warn:
            warnAddOn = (session, status)
        }
    }

    /// Launch from the CoachDecision engine. Every trainable recommendation lands
    /// on that workout's setup/settings surface first — never directly into an
    /// active recorder (audio/coach routing plan §D). The recorder begins only
    /// after the user confirms from the setup screen.
    private func launchDecision(_ session: CoachSession) {
        switch session.launchPayload {
        case .strengthPlan:
            if let plan = EditablePlan.from(coach: session) {
                path.append(HomeRoute.workoutEditor(plan))
            }
        case .cardio(let cardioTypeStr, let durationMinutes):
            switch cardioTypeStr {
            case "walk": startOutdoorWithGoal(.walk)     // → CardioGoalSheet → HR gate → recorder
            case "run": startOutdoorWithGoal(.run)
            case "cycle": startOutdoorWithGoal(.cycle)
            case "swim": swimPresented = true            // SwimRecordView opens to its setup screen
            case "hiit": intervalType = .hiit            // → IntervalSetupView (protocol picker)
            case "boxing": intervalType = .boxing        // → IntervalSetupView (boxing rounds)
            case "rowing":
                timerCardioSetup = TimerCardioSetup(type: .rowing, suggestedMinutes: durationMinutes)
            default:
                timerCardioSetup = TimerCardioSetup(type: .other, suggestedMinutes: durationMinutes)
            }
        case .recovery, .rest, .assessment:
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

    private func handleEditorStart(_ plan: EditablePlan) {
        pendingPlan = plan
        if plan.warmupMinutes > 0 {
            startWarmupAfterHRGate = true
        }
        proceedFromHRGate(.strength, useHR: false)
    }

    private func materializePlan(_ plan: EditablePlan) throws -> WorkoutSession {
        let session = try WorkoutRepository.createSession(title: plan.title, in: context)
        session.plannedExerciseNames = plan.exercises.map(\.name)
        if let first = plan.exercises.first, !first.sets.isEmpty {
            session.plannedRepLadder = first.sets.map(\.targetReps)
        }
        let weights = plan.exercises.compactMap(\.sets.first?.targetWeight)
        if let w = weights.first, w > 0, weights.allSatisfy({ $0 == w }) {
            session.prescribedLoadKg = w
        }
        for name in plan.exercises.map(\.name) {
            _ = try WorkoutRepository.findOrCreateExercise(named: name, in: context)
        }
        session.cooldownSeconds = Double(plan.cooldownMinutes * 60)
        session.activePartnerIDs = plan.partnerIDs.map(\.uuidString)
        let rirNotes = plan.exercises.compactMap { ex -> String? in
            guard !ex.notes.isEmpty, ex.notes.contains("RIR") else { return nil }
            return ex.notes
        }
        if !rirNotes.isEmpty { session.notes = rirNotes.joined(separator: "; ") }
        try context.save()
        return session
    }
}

/// What to launch once the countdown finishes.
struct PendingWorkout: Identifiable {
    let id = UUID()
    enum Kind { case strength, plan(WorkoutPlan, [Int]?), reuse(WorkoutSession), outdoor(CardioType), interval(IntervalLaunch), timer(CardioType)
        var isStrength: Bool {
            switch self {
            case .strength, .plan, .reuse: true
            case .outdoor, .interval, .timer: false
            }
        }
        var cardioType: CardioType? {
            switch self {
            case .outdoor(let c), .timer(let c): return c
            case .strength, .plan, .reuse, .interval: return nil
            }
        }
    }
    let kind: Kind
}

private enum WorkoutStartCue {
    case countdown, single, none
}

/// Pushed destinations reachable from Home.
enum HomeRoute: Hashable {
    case history, settings, coach, coachPreview, coachPreferences, planning
    case yourPlan
    case workoutEditor(EditablePlan)
}
