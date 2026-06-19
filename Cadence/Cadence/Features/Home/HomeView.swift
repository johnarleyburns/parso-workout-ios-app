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
    /// Coach prescription stashed while the HR gate is shown.
    @State private var pendingPrescription: Recommendation?
    @State private var warmupActive = false
    @State private var today: DayActivity?
    @State private var coachDayToken = Date()
    @State private var homeSessionToDelete: WorkoutSession?
    @State private var homeCardioToDelete: CardioWorkout?
    @State private var pendingPlan: EditablePlan?
    @State private var captureHR = false
    // Quick-start shortcuts from the stat tiles (feedback batch 8).
    @State private var cardioPickerPresented = false  // cardio-min tile → cardio-only picker
    @State private var weightsStartPresented = false  // volume tile → strength start
    @State private var bodyPartsPresented = false     // body-parts tile → fill-the-gaps
    @State private var cardioGoalFor: CardioType?     // optional distance goal before run/walk/cycle
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

    var body: some View {
        @Bindable var active = active
        return ZStack {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let s = active.strengthSession { resumeCard(s) }
                    CoachCardView(recommendation: coachRecommendation,
                                  insightCount: coachInsights.count,
                                  unit: settings.unit,
                                  onSeeAll: { path.append(HomeRoute.coach) })
                    coachStartButton
                    startButton
                    cardioButton
                    logButton
                    planningButton
                    thisWeekSection
                    recentWorkoutsSection
                }
                .padding()
            }
            .navigationTitle("Cladiron")
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
                    WorkoutSummaryView(data: .from(cardio: c))
                }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .history: HistoryView(path: $path)
                case .settings: SettingsView()
                case .coach: CoachInsightsView(insights: coachInsights)
                case .planning: PlanningView(switchToWorkout: { path = NavigationPath() })
                }
            }
            .task { today = await model.health.todayActivity(); await syncCardioFromHealth() }
            .refreshable { today = await model.health.todayActivity(); await syncCardioFromHealth() }
            .sheet(isPresented: $logPickerPresented) {
                LogWorkoutPicker()
            }
            // P1 #9 — the post-workout summary is presented here, above the whole
            // NavigationStack, so the finished session can pop behind it.
            .fullScreenCover(item: $active.finishedSummary) { finished in
                WorkoutSummaryView(data: finished.data,
                                   onDone: { active.finishedSummary = nil })
            }
            .sheet(item: $cardioType) { RecordCardioView(initialType: $0, customTitle: otherCardioTitle, captureHR: captureHR) }
            .fullScreenCover(item: $outdoorType) { OutdoorCardioView(type: $0, customTitle: otherCardioTitle, goalMeters: outdoorGoalMeters, captureHR: captureHR) }
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
            // Body-parts tile (batch 8) → fill-the-gaps quick start.
            .sheet(isPresented: $bodyPartsPresented) {
                BodyPartQuickStartView(missing: bodyPartsThisWeek.missing) { session in
                    bodyPartsPresented = false
                    active.startStrength(session); path.append(session)
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
            .fullScreenCover(item: $intervalLaunch) { IntervalView(plan: $0.plan, saveType: $0.saveType, captureHR: captureHR) }
            .fullScreenCover(isPresented: $swimPresented) { SwimRecordView() }
            .confirmationDialog("Delete this workout?",
                                isPresented: Binding(get: { homeSessionToDelete != nil },
                                                     set: { if !$0 { homeSessionToDelete = nil } }),
                                presenting: homeSessionToDelete) { session in
                Button("Delete", role: .destructive) {
                    try? WorkoutRepository.softDeleteSession(session, in: context)
                    homeSessionToDelete = nil
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
                }
                Button("Cancel", role: .cancel) { homeCardioToDelete = nil }
            } message: { _ in Text("You can restore it from History → View Deleted.") }
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
                coachDayToken = Date()
            }
        }
    }

    private static func dayString(_ date: Date = Date()) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }

    // MARK: Top stats

    private var statRow: some View {
        let totalWorkouts = workoutsThisWeek
        let cardio = cardioMinutesThisWeek
        let cardioGoal = max(1, settings.weeklyCardioMinutesGoal)
        return HStack(spacing: 14) {
            statTile("\(totalWorkouts)", "workouts this week",
                     id: "today.steps")
            statTile("\(cardio) / \(cardioGoal)", "cardio min this week",
                     id: "home.cardioMinutes",
                     progress: Double(cardio) / Double(cardioGoal), progressID: "home.cardioMinutes.progress")
        }
    }

    /// "This week" insights — the batch-8 stat tiles, demoted below the Coach card
    /// and the action spine (strength-pivot P3, §05). Their tap-to-start behavior
    /// and a11y ids are unchanged.
    private var thisWeekSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This week").font(.headline)
                .accessibilityIdentifier("home.thisWeek")
            statRow
            coverageRow
        }
    }

    /// Volume + body-part coverage for the trailing week (feedback batch 3).
    private var coverageRow: some View {
        let coverage = bodyPartsThisWeek
        return HStack(spacing: 14) {
            statTile(Format.weight(volumeThisWeekKg, unit: settings.unit, decimals: 0),
                     "volume this week", id: "home.volume",
                     tileID: "home.volumeTile", onTap: { weightsStartPresented = true })
            statTile("\(coverage.hit.count)/\(BodyPart.allCases.count)", "body parts",
                     id: "home.bodyParts",
                     caption: coverage.missing.isEmpty
                        ? "All parts hit 💪"
                        : "Missing: " + coverage.missing.map(\.displayName).joined(separator: ", "),
                     captionID: "home.bodyParts.missing",
                     tileID: "home.bodyPartsTile", onTap: { bodyPartsPresented = true })
        }
    }

    private func statTile(_ value: String, _ label: String, id: String,
                          caption: String? = nil, captionID: String? = nil,
                          progress: Double? = nil, progressID: String? = nil,
                          tileID: String? = nil, onTap: (() -> Void)? = nil) -> some View {
        let content = VStack(spacing: 4) {
            Text(value).font(.title.bold()).monospacedDigit().accessibilityIdentifier(id)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(.secondary)
            if let progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(.green)
                    .accessibilityIdentifier(progressID ?? "")
                    .padding(.top, 2).padding(.horizontal, 4)
            }
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(captionID ?? "")
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16).padding(.horizontal, 6)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())

        return Group {
            if let onTap {
                // A tappable tile is a fast path to start the workout it summarizes
                // (feedback batch 8). Plain style keeps the card's look.
                Button { Haptics.selection(); onTap() } label: { content }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(tileID ?? "")
                    .accessibilityAddTraits(.isButton)
            } else {
                content
            }
        }
    }

    /// Pulls any new Watch/Health-recorded cardio into the local store (FR-2.1).
    /// Formerly auto-run by the now-removed Cardio screen (feedback batch 3).
    private func syncCardioFromHealth() async {
        let new = await model.health.newWorkouts(since: model.lastHealthSync)
        _ = try? WorkoutRepository.ingest(new, in: context)
        model.lastHealthSync = Date()
    }

    // Coach "Start Coach Workout" button — sits between the Coach card and
    // "Start Workout".  Launches the prescribed session through the HR gate.
    private var coachStartButton: some View {
        Button { Haptics.selection(); launchPrescription(coachRecommendation) } label: {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start Coach Workout").font(.headline)
                    Text(coachRecommendation.action)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.subheadline).opacity(0.8)
            }
            .padding(.vertical, 14).padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
            .background(.green, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.coachStart")
        .accessibilityLabel("Start Coach Workout — \(coachRecommendation.title)")
    }

    private var startButton: some View {
        Button { Haptics.selection(); weightsStartPresented = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "dumbbell.fill").font(.headline)
                Text("Start Strength Workout").font(.headline)
                Spacer()
                Image(systemName: "chevron.right").font(.subheadline).opacity(0.6)
            }
            .padding(.vertical, 14).padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.tint)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.startWorkout").accessibilityLabel("Start a strength workout")
    }

    private var cardioButton: some View {
        Button { Haptics.selection(); cardioPickerPresented = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "figure.run").font(.headline)
                Text("Start Cardio").font(.headline)
                Spacer()
                Image(systemName: "chevron.right").font(.subheadline).opacity(0.6)
            }
            .padding(.vertical, 14).padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.tint)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.startCardio")
        .accessibilityLabel("Start a cardio workout")
    }

    /// Log a past workout manually (feedback batch 6 item 3) — it lands in history
    /// just like a live one, flagged "Logged".
    private var logButton: some View {
        Button { Haptics.selection(); logPickerPresented = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil").font(.headline)
                Text("Log Workout").font(.headline)
                Spacer()
                Image(systemName: "chevron.right").font(.subheadline).opacity(0.6)
            }
            .padding(.vertical, 14).padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.tint)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.logWorkout").accessibilityLabel("Log a past workout")
    }

    private var planningButton: some View {
        Button { Haptics.selection(); path.append(HomeRoute.planning) } label: {
            HStack(spacing: 10) {
                Image(systemName: "books.vertical").font(.headline)
                Text("Programs & Routines").font(.headline)
                Spacer()
                Image(systemName: "chevron.right").font(.subheadline).opacity(0.6)
            }
            .padding(.vertical, 14).padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.tint)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.planning").accessibilityLabel("Programs and routines")
    }

    // MARK: Inline sections (surfaced, not hidden)

    /// One merged, date-sorted "Recent workouts" list — cardio counts as a workout
    /// too, so strength sessions and cardio recordings share a single section (P1 #10).
    private var recentItems: [RecentWorkoutItem] {
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
        // "Do this workout" path: launch the prescription immediately (fast path).
        if let rec = pendingPrescription {
            pendingPrescription = nil
            let prescribed = rec.prescribedSession()
            if let s = try? WorkoutRepository.startSession(from: prescribed, in: context) {
                active.startStrength(s)
                path.append(s)
                WorkoutCues.startBeepSequence(enabled: settings.workoutSounds)
            }
            return
        }
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

    /// "Do this workout" (strength-pivot P5.3): materialize the coach's top
    /// recommendation into a fresh strength session pre-filled with the prescribed
    /// movement, planned sets/reps, and load — the fast default path. Routes
    /// through the HR gate so the user can verify live HR first.
    private func launchPrescription(_ rec: Recommendation) {
        pendingPrescription = rec
        proceedFromHRGate(.strength, useHR: false)
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
enum HomeRoute: Hashable { case history, settings, coach, planning }

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
