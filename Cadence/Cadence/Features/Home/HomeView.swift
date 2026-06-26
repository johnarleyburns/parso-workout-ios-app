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
    /// Bumped after any workout-history mutation (save, log, ingest, delete) so the
    /// computed Coach / This Week / recent surfaces recompute immediately — without
    /// waiting for `scenePhase == .active` (the old "only fixed after re-entry" bug).
    @State private var historyRefreshToken = UUID()
    /// Setup surface for non-GPS timer cardio (rowing/other) launched from Coach.
    @State private var timerCardioSetup: TimerCardioSetup?
    @State private var homeSessionToDelete: WorkoutSession?
    @State private var homeCardioToDelete: CardioWorkout?
    @State private var pendingPlan: EditablePlan?
    @State private var captureHR = false
    // Quick-start shortcuts from the stat tiles (feedback batch 8).
    @State private var cardioPickerPresented = false  // cardio-min tile → cardio-only picker
    @State private var weightsStartPresented = false  // volume tile → strength start
    @State private var cardioGoalFor: CardioType?     // optional distance goal before run/walk/cycle
    @State private var warnAddOn: (session: CoachSession, status: CoachAddOnStatus)?
    @State private var outdoorGoalMeters: Double?     // goal handed to the outdoor recorder

    // Weekly tiles (feedback batch 3) — pure aggregates from CadenceCore.
    private var weekStart: Date { WeeklyStats.weekStart() }
    private var cardioMinutesThisWeek: Int { WeeklyStats.cardioMinutes(cardio, since: weekStart) }
    private var volumeThisWeekKg: Double { WeeklyStats.volumeKg(sessions, since: weekStart) }
    private var bodyPartsThisWeek: (hit: Set<BodyPart>, missing: [BodyPart]) {
        WeeklyStats.bodyParts(sessions, since: weekStart)
    }

    private var workoutsThisWeek: Int {
        let ws = weekStart
        let strengthCount = sessions.filter { $0.date >= ws && $0.deletedAt == nil }.count
        let cardioCount = cardio.filter { $0.start >= ws && $0.deletedAt == nil }.count
        return strengthCount + cardioCount
    }

    // Coach engine (strength-pivot P3/P5): one computed snapshot drives both the
    // read-only insights and the prescriptive recommendation surfaced on the card.
    private var coachFacts: TrainingFacts {
        TrainingFacts.make(sessions: sessions.filter { $0.deletedAt == nil },
                           assessments: assessments,
                           goal: settings.trainingGoal,
                           experience: settings.experienceLevel,
                           formula: settings.formula)
    }
    private var coachInsights: [Insight] { InsightEngine.run(coachFacts) }
    /// The top prescription the Coach card leads with (P5.2). Never nil — the engine
    /// falls back to a cited cold-start starter when there's no history yet.
    private var coachRecommendation: Recommendation { RecommendationEngine.top(coachFacts) }

    private var coachDecision: CoachDecision {
        _ = historyRefreshToken
        let events = buildTrainingEvents()
        let facts = CoachFacts.make(from: events, goal: settings.trainingGoal,
                                     experience: settings.experienceLevel,
                                     formula: settings.formula)
        let today = Calendar.current.startOfDay(for: Date())
        let todayReadiness = readinessEntries.first { Calendar.current.startOfDay(for: $0.date) == today }
        let hasPain = todayReadiness?.hasPainOrIllnessConcern ?? false
        return CoachDecisionEngine.run(facts,
                                         profile: settings.coachPreferenceProfile,
                                         schedulePreferences: settings.coachSchedulePreferences,
                                         hasPainConcern: hasPain)
    }

    private var addOnRecommendation: CoachAddOnRecommendation {
        guard case .planComplete = coachDecision.planAdherence else { return .empty }
        let events = buildTrainingEvents()
        let facts = CoachFacts.make(from: events, goal: settings.trainingGoal,
                                     experience: settings.experienceLevel,
                                     formula: settings.formula)
        let today = Calendar.current.startOfDay(for: Date())
        let todayReadiness = readinessEntries.first { Calendar.current.startOfDay(for: $0.date) == today }
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
                    CoachDecisionCardView(
                        decision: coachDecision,
                        addOnRecommendation: addOnRecommendation,
                        onStart: { launchDecision($0) },
                        onAddOn: { session, status in handleAddOn(session, status) },
                        onSeeWeek: { path.append(HomeRoute.yourWeek) },
                        onSeeWhy: { path.append(HomeRoute.whyToday) },
                        onSeeTomorrow: { path.append(HomeRoute.yourWeek) })
                    quickActionsRow
                    thisWeekCard
                    favoritesSection
                    recentWorkoutsSection
                }
                .padding()
            }
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
                // A5 — history rows open the read-only summary; strength offers Edit
                // (pushes the live session into the set editor).
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
                case .coach: CoachInsightsView(insights: coachInsights)
                case .planning: PlanningView(switchToWorkout: { path = NavigationPath() })
                case .yourWeek:
                    let facts = CoachFacts.make(
                        from: buildTrainingEvents(), goal: settings.trainingGoal,
                        experience: settings.experienceLevel, formula: settings.formula)
                    YourWeekView(decision: coachDecision, facts: facts,
                                 preferences: settings.coachSchedulePreferences)
                case .whyToday:
                    WhyThisTodayView(decision: coachDecision,
                                     onAltTap: { path.append(HomeRoute.coachAlternatives) })
                case .coachAlternatives:
                    CoachAlternativesView(decision: coachDecision,
                                          onSelect: { session in
                        settings.recordCoachSelection(session,
                                                      alternatives: coachDecision.alternatives)
                        launchDecision(session)
                        path = NavigationPath()
                    })
                case .workoutEditor(let plan):
                    WorkoutPlanEditor(plan: plan, onStart: { plan in
                        handleEditorStart(plan)
                        path = NavigationPath()
                    })
                }
            }
            .task { today = await model.health.todayActivity(); await syncCardioFromHealth() }
            .refreshable { today = await model.health.todayActivity(); await syncCardioFromHealth() }
            .sheet(isPresented: $logPickerPresented) {
                LogWorkoutPicker(onSaved: markWorkoutHistoryChanged)
            }
            // P1 #9 — the post-workout summary is presented here, above the whole
            // NavigationStack, so the finished session can pop behind it.
            .fullScreenCover(item: $active.finishedSummary) { finished in
                WorkoutSummaryView(data: finished.data,
                                   onDone: { active.finishedSummary = nil })
            }
            .sheet(item: $cardioType) { RecordCardioView(initialType: $0, customTitle: otherCardioTitle, captureHR: captureHR, onSaved: { _ in markWorkoutHistoryChanged() }) }
            .fullScreenCover(item: $outdoorType) { OutdoorCardioView(type: $0, customTitle: otherCardioTitle, goalMeters: outdoorGoalMeters, captureHR: captureHR, onSaved: { _ in markWorkoutHistoryChanged() }) }
            .sheet(item: $timerCardioSetup) { setup in
                TimerCardioSetupView(type: setup.type, suggestedMinutes: setup.suggestedMinutes,
                                     onSaved: { _ in markWorkoutHistoryChanged() })
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
            .fullScreenCover(item: $intervalLaunch) { IntervalView(plan: $0.plan, saveType: $0.saveType, captureHR: captureHR, onSaved: { _ in markWorkoutHistoryChanged() }) }
            .fullScreenCover(isPresented: $swimPresented) { SwimRecordView(onSaved: { _ in markWorkoutHistoryChanged() }) }
            .confirmationDialog("Delete this workout?",
                                isPresented: Binding(get: { homeSessionToDelete != nil },
                                                     set: { if !$0 { homeSessionToDelete = nil } }),
                                presenting: homeSessionToDelete) { session in
                Button("Delete", role: .destructive) {
                    try? WorkoutRepository.softDeleteSession(session, in: context)
                    homeSessionToDelete = nil
                    markWorkoutHistoryChanged()
                }
                Button("Cancel", role: .cancel) { homeSessionToDelete = nil }
            } message: { _ in Text("You can restore it from History → View Deleted.") }
            .confirmationDialog("Delete this cardio workout?",
                                isPresented: Binding(get: { homeCardioToDelete != nil },
                                                     set: { if !$0 { homeCardioToDelete = nil } }),
                                presenting: homeCardioToDelete) { c in
                Button("Delete", role: .destructive) {
                    try? WorkoutRepository.softDeleteCardio(c, in: context)
                    homeCardioToDelete = nil
                    markWorkoutHistoryChanged()
                }
                Button("Cancel", role: .cancel) { homeCardioToDelete = nil }
            } message: { _ in Text("You can restore it from History → View Deleted.") }
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
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) {
                        launch(.strength)
                        // Record the actual warm-up time on the session just created
                        // (feedback batch 6).
                        active.strengthSession?.warmupSeconds = Double(secs)
                        try? context.save()
                        warmupActive = false
                    }
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
        }
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
    }

    private func quickAction(_ title: String, _ symbol: String, id: String,
                             action: @escaping () -> Void) -> some View {
        Button { Haptics.selection(); action() } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(.tint)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    /// "This week" at a glance — one calm card, not four launcher tiles.
    private var thisWeekCard: some View {
        _ = historyRefreshToken
        let balance = coachDecision.weeklyBalance
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This week").font(.headline)
                Spacer()
                Button { Haptics.selection(); path.append(HomeRoute.coach) } label: {
                    HStack(spacing: 3) {
                        Text("Details").font(.caption)
                        Image(systemName: "chevron.right").font(.caption2)
                    }.foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 0) {
                weekMetric("\(balance.strengthDays)", "strength", id: "home.workoutsCount")
                weekMetric("\(Int(balance.moderateEquivalentMinutes))", "min", id: "home.cardioMinutes")
                weekMetric(compactVolume(), "volume", id: "home.volume")
                weekMetric("\(bodyPartsThisWeek.hit.count)/\(BodyPart.allCases.count)",
                           "parts", id: "home.bodyParts")
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("home.thisWeek")
    }

    private func weekMetric(_ value: String, _ label: String, id: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.bold()).monospacedDigit()
                .minimumScaleFactor(0.5).lineLimit(1)
                .accessibilityIdentifier(id)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Compact weekly volume for the calm 4-across row (e.g. "12.4k"); the unit
    /// is implied by Settings and shown in full on the Details screen.
    private func compactVolume() -> String {
        let value = settings.unit == .pounds ? volumeThisWeekKg * 2.2046226 : volumeThisWeekKg
        if value >= 1000 { return String(format: "%.1fk", value / 1000) }
        return String(format: "%.0f", value)
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
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: Inline sections (surfaced, not hidden)

    /// One merged, date-sorted "Recent workouts" list — cardio counts as a workout
    /// too, so strength sessions and cardio recordings share a single section (P1 #10).
    private var recentItems: [RecentWorkoutItem] {
        _ = historyRefreshToken
        let merged = sessions.filter { $0.deletedAt == nil }.map { RecentWorkoutItem.strength($0) }
                   + cardio.filter { $0.deletedAt == nil }.map { RecentWorkoutItem.cardio($0) }
        return Array(merged.sorted { $0.date > $1.date }.prefix(5))
    }

    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Recent workouts", route: .history, id: "home.train")
            if recentItems.isEmpty {
                Text("No workouts yet.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(recentItems) { item in
                switch item {
                case .strength(let s): strengthRow(s)
                case .cardio(let w): cardioRow(w)
                }
            }
        }
    }

    private func strengthRow(_ s: WorkoutSession) -> some View {
        Button { Haptics.selection(); path.append(HistorySummaryRoute.strength(s)) } label: {
            HStack {
                Image(systemName: s.symbol).foregroundStyle(.tint).frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(s.title.isEmpty ? "Workout" : s.title)
                        if s.isLogged { LoggedTag() }
                    }
                    Text("\(s.orderedSets.count) sets").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(s.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.sessionRow")
        .swipeActions {
            Button(role: .destructive) { homeSessionToDelete = s } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func cardioRow(_ w: CardioWorkout) -> some View {
        Button { Haptics.selection(); path.append(HistorySummaryRoute.cardio(w)) } label: {
            HStack {
                Image(systemName: w.typeValue.symbol).foregroundStyle(.tint).frame(width: 26)
                Text(w.displayTitle)
                if w.isLogged { LoggedTag() }
                Spacer()
                Text(w.start.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.cardioRow.\(w.typeValue.rawValue)")
        .swipeActions {
            Button(role: .destructive) { homeCardioToDelete = w } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func sectionHeader(_ title: String, route: HomeRoute, id: String) -> some View {
        Button { Haptics.selection(); path.append(route) } label: {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("See all").font(.caption)
                Image(systemName: "chevron.right").font(.caption)
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
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
            .background(.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
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
    private func launch(_ kind: PendingWorkout.Kind) {
        switch kind {
        case .strength:
            if let plan = pendingPlan {
                pendingPlan = nil
                if let s = try? materializePlan(plan) {
                    active.startStrength(s); path.append(s)
                    WorkoutCues.startBeepSequence(enabled: settings.workoutSounds)
                }
            } else if let s = try? WorkoutRepository.createSession(title: "Workout", in: context) {
                active.startStrength(s); path.append(s)
                WorkoutCues.startBeepSequence(enabled: settings.workoutSounds)
            }
        case .plan(let plan, let ladder):
            if let s = try? WorkoutRepository.startSession(from: plan, repLadder: ladder, in: context) {
                active.startStrength(s); path.append(s)
                WorkoutCues.startBeepSequence(enabled: settings.workoutSounds)
            }
        case .reuse(let past):
            if let s = try? WorkoutRepository.reuseSession(from: past, in: context) {
                active.startStrength(s); path.append(s)
                WorkoutCues.startBeepSequence(enabled: settings.workoutSounds)
            }
        case .outdoor(let c): outdoorType = c
        case .interval(let l): intervalLaunch = l
        case .timer(let c): cardioType = c
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

/// Pushed destinations reachable from Home.
enum HomeRoute: Hashable {
    case history, settings, coach, planning
    case yourWeek
    case whyToday
    case coachAlternatives
    case workoutEditor(EditablePlan)
}

/// A row in Home's merged "Recent workouts" list — strength and cardio together,
/// sorted by date (P1 #10).
enum RecentWorkoutItem: Identifiable {
    case strength(WorkoutSession)
    case cardio(CardioWorkout)

    var id: String {
        switch self {
        case .strength(let s): return "s-\(s.id.uuidString)"
        case .cardio(let c): return "c-\(c.id.uuidString)"
        }
    }
    var date: Date {
        switch self {
        case .strength(let s): return s.date
        case .cardio(let c): return c.start
        }
    }
}

/// A history row's read-only summary destination (field-testing Round 4 A5).
/// Wraps the `@Model` row (already `Hashable`) so the big `WorkoutSummaryData`
/// value type needn't be `Hashable`.
enum HistorySummaryRoute: Hashable {
    case strength(WorkoutSession)
    case cardio(CardioWorkout)
}
