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
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \CardioWorkout.start, order: .reverse) private var cardio: [CardioWorkout]

    @State private var typePickerPresented = false
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
    @State private var warmupActive = false
    @State private var today: DayActivity?
    // Quick-start shortcuts from the stat tiles (feedback batch 8).
    @State private var stepsQuickStart = false        // steps tile → Run/Walk dialog
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

    var body: some View {
        @Bindable var active = active
        return ZStack {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let s = active.strengthSession { resumeCard(s) }
                    startButton
                    logButton
                    statRow
                    coverageRow
                    recentWorkoutsSection
                }
                .padding()
            }
            .navigationTitle("Cadence")
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
                }
            }
            .task { today = await model.health.todayActivity(); await syncCardioFromHealth() }
            .refreshable { today = await model.health.todayActivity(); await syncCardioFromHealth() }
            .sheet(isPresented: $typePickerPresented) {
                WorkoutTypePicker(onSelect: { start($0) },
                                  onPlan: { plan, ladder in launchFromPicker(.plan(plan, ladder)) },
                                  onWeightsQuickStart: { launchFromPicker(.strength, skipCountdown: true) },
                                  onWeightsWarmup: { typePickerPresented = false; warmupActive = true },
                                  onWeightsReuse: { launchFromPicker(.reuse($0)) },
                                  onOtherCardio: { desc, gps in startOtherCardio(description: desc, gps: gps) })
            }
            .sheet(isPresented: $logPickerPresented) {
                LogWorkoutPicker()
            }
            // P1 #9 — the post-workout summary is presented here, above the whole
            // NavigationStack, so the finished session can pop behind it.
            .fullScreenCover(item: $active.finishedSummary) { finished in
                WorkoutSummaryView(data: finished.data,
                                   onDone: { active.finishedSummary = nil })
            }
            .sheet(item: $cardioType) { RecordCardioView(initialType: $0, customTitle: otherCardioTitle) }
            .fullScreenCover(item: $outdoorType) { OutdoorCardioView(type: $0, customTitle: otherCardioTitle, goalMeters: outdoorGoalMeters) }
            // Steps tile (batch 8) → start an outdoor Run or Walk fast.
            .confirmationDialog("Start a workout", isPresented: $stepsQuickStart, titleVisibility: .visible) {
                Button("Start Run") { startOutdoorWithGoal(.run) }.accessibilityIdentifier("steps.run")
                Button("Start Walk") { startOutdoorWithGoal(.walk) }.accessibilityIdentifier("steps.walk")
                Button("Cancel", role: .cancel) { }
            }
            // Cardio-min tile (batch 8) → the Start picker filtered to cardio types.
            .sheet(isPresented: $cardioPickerPresented) {
                WorkoutTypePicker(onSelect: { cardioPickerPresented = false; start($0) },
                                  onPlan: { _, _ in },
                                  onWeightsQuickStart: { }, onWeightsWarmup: { },
                                  onWeightsReuse: { _ in },
                                  onOtherCardio: { desc, gps in cardioPickerPresented = false; startOtherCardio(description: desc, gps: gps) },
                                  types: [.run, .walk, .cycle, .swim, .hiit, .boxing, .other],
                                  title: "Start Cardio")
            }
            // Volume tile (batch 8) → strength start (Quick Start / Warm-Up / Reuse / presets).
            .sheet(isPresented: $weightsStartPresented) {
                NavigationStack {
                    WeightsStartView(
                        onQuickStart: { weightsStartPresented = false; launchFromPicker(.strength, skipCountdown: true) },
                        onWarmupStart: { weightsStartPresented = false; warmupActive = true },
                        onReuse: { weightsStartPresented = false; launchFromPicker(.reuse($0)) },
                        onPlan: { plan, ladder in weightsStartPresented = false; launchFromPicker(.plan(plan, ladder)) })
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
            .fullScreenCover(item: $intervalLaunch) { IntervalView(plan: $0.plan, saveType: $0.saveType) }
            .fullScreenCover(isPresented: $swimPresented) { SwimRecordView() }
        }

        // Get-ready countdown as a plain opaque overlay above the whole
        // NavigationStack — not a fullScreenCover (P1 #5 follow-up). As a sibling
        // view (not a modal) it can appear in the same frame the Start sheet
        // dismisses, so Home never shows between the two. On finish we push the
        // session and drop the overlay in one animation-disabled transaction, so the
        // session is already on screen when the overlay vanishes — no Home flash
        // before the warm-up, and none after it.
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
                minutes: settings.warmupMinutes,
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
    }

    // MARK: Top stats

    private var statRow: some View {
        let steps = today?.steps ?? 0
        let stepGoal = max(1, settings.stepGoal)
        let cardio = cardioMinutesThisWeek
        let cardioGoal = max(1, settings.weeklyCardioMinutesGoal)
        return HStack(spacing: 14) {
            statTile("\(Format.integer(steps)) / \(Format.integer(stepGoal))", "steps today",
                     id: "today.steps",
                     progress: Double(steps) / Double(stepGoal), progressID: "today.steps.progress",
                     tileID: "home.stepsTile", onTap: { stepsQuickStart = true })
            statTile("\(cardio) / \(cardioGoal)", "cardio min this week",
                     id: "home.cardioMinutes",
                     progress: Double(cardio) / Double(cardioGoal), progressID: "home.cardioMinutes.progress",
                     tileID: "home.cardioTile", onTap: { cardioPickerPresented = true })
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

    private var startButton: some View {
        Button { Haptics.selection(); typePickerPresented = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill").font(.largeTitle)
                Text("Start Workout").font(.title2.bold())
                Spacer()
                Image(systemName: "chevron.right").font(.headline).opacity(0.8)
            }
            .padding(.vertical, 22).padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 84)
            .foregroundStyle(.white)
            .background(LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.startWorkout").accessibilityLabel("Start a workout")
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

    // MARK: Inline sections (surfaced, not hidden)

    /// One merged, date-sorted "Recent workouts" list — cardio counts as a workout
    /// too, so strength sessions and cardio recordings share a single section (P1 #10).
    private var recentItems: [RecentWorkoutItem] {
        let merged = sessions.map { RecentWorkoutItem.strength($0) } + cardio.map { RecentWorkoutItem.cardio($0) }
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
            // Swimming is a minimal time + laps recorder (feedback #3).
            typePickerPresented = false; swimPresented = true
        } else if type.usesGPS, let c = type.cardioType {
            // Run/Walk/Cycle: offer an optional distance goal first (batch 8).
            typePickerPresented = false; startOutdoorWithGoal(c)
        } else if type == .hiit || type == .boxing {
            typePickerPresented = false; intervalType = type
        } else if let c = type.cardioType {
            typePickerPresented = false; begin(.timer(c))
        }
    }
    /// "Other Cardio" chosen (feedback batch 6 item 3): stash its description, then
    /// route to the GPS recorder or the indoor timer per the user's GPS toggle.
    private func startOtherCardio(description: String, gps: Bool) {
        typePickerPresented = false
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
    /// flash (P1 #1/#5): with no countdown, push the session *under* the still-open
    /// sheet and then dismiss it (revealing the session); with a countdown, dismiss
    /// first and present the countdown.
    /// `skipCountdown` makes "Quick Start" truly immediate — no get-ready countdown,
    /// regardless of the Settings value (which still applies to library/reuse/warm-up).
    private func launchFromPicker(_ kind: PendingWorkout.Kind, skipCountdown: Bool = false) {
        if skipCountdown || settings.preWorkoutCountdown <= 0 {
            launch(kind)
            typePickerPresented = false
        } else {
            typePickerPresented = false
            pending = PendingWorkout(kind: kind)
        }
    }
    private func begin(_ kind: PendingWorkout.Kind) {
        if settings.preWorkoutCountdown <= 0 { launch(kind) } else { pending = PendingWorkout(kind: kind) }
    }
    private func launch(_ kind: PendingWorkout.Kind) {
        switch kind {
        case .strength:
            if let s = try? WorkoutRepository.createSession(title: "Workout", in: context) {
                active.startStrength(s); path.append(s)
                WorkoutCues.transition(enabled: settings.workoutSounds)   // workout starts (item 9)
            }
        case .plan(let plan, let ladder):
            if let s = try? WorkoutRepository.startSession(from: plan, repLadder: ladder, in: context) {
                active.startStrength(s); path.append(s)
                WorkoutCues.transition(enabled: settings.workoutSounds)
            }
        case .reuse(let past):
            if let s = try? WorkoutRepository.reuseSession(from: past, in: context) {
                active.startStrength(s); path.append(s)
                WorkoutCues.transition(enabled: settings.workoutSounds)
            }
        case .outdoor(let c): outdoorType = c
        case .interval(let l): intervalLaunch = l
        case .timer(let c): cardioType = c
        }
    }
}

/// What to launch once the countdown finishes.
struct PendingWorkout: Identifiable {
    let id = UUID()
    enum Kind { case strength, plan(WorkoutPlan, [Int]?), reuse(WorkoutSession), outdoor(CardioType), interval(IntervalLaunch), timer(CardioType) }
    let kind: Kind
}

/// Pushed destinations reachable from Home.
enum HomeRoute: Hashable { case history, settings }

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
