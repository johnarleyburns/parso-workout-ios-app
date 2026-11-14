import SwiftUI
import SwiftData
import WatchConnectivity
import CadenceCore
import CadenceFeatures

struct WatchRootView: View {
    @Environment(WatchWorkoutManager.self) var watchManager
    @Environment(AppSettings.self) var watchAppSettings
    @Environment(\.modelContext) private var context
    /// Only unfinished Watch sessions: the launcher needs one resumable row,
    /// not the whole training log fetched on the main actor at launch and
    /// again on every store change.
    // Keep the store predicate intentionally small so SwiftData's macro can
    // type-check it quickly on watchOS. `isResumable` applies the remaining
    // deleted/logged checks in memory below.
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil },
           sort: \WorkoutSession.date, order: .reverse)
    private var resumableSessions: [WorkoutSession]

    @State private var cardioLocation: WorkoutConfigurationSpec.Location = .outdoor
    @AppStorage("watch.swim.poolLength") private var cardioLapLength: Double = 25
    @State private var plannedSwimSpec: WorkoutConfigurationSpec?
    @State private var cardioStartError: String?
    @State private var activeCardioKind: WorkoutConfigurationSpec.CardioKind?
    @State private var activeCardioSpec: WorkoutConfigurationSpec?
    @State private var activeIntervalSession: ActiveIntervalSession?
    @State private var plannedStrengthSession: WatchSync.TodayPlan.Session?
    @State private var resumingSession: WorkoutSession?
    @State private var confirmDiscardResume = false
    @State private var startingQuickLift = false
    @State private var showingCardio = false
    @State private var showingWorkoutChoice = false
    private let launchRequests = WatchLaunchRequests.shared

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let intervalSession: ActiveIntervalSession?
        if arguments.contains("-uiTestBoxingInterval") {
            let model = IntervalSetupModel(kind: "Boxing")
            intervalSession = ActiveIntervalSession(plan: model.intervalPlan(), kind: "Boxing")
        } else {
            intervalSession = nil
        }
        _activeIntervalSession = State(initialValue: intervalSession)
    }

    var body: some View {
        Group {
            if watchManager.needsInitialHealthAuthorization && !watchManager.isActive && !watchManager.isMonitoring {
                WatchHealthAuthorizationView()
            } else if watchManager.isPhoneOwnedWorkoutActive {
                WatchPhoneWorkoutView()
            } else if let activeIntervalSession {
                WatchIntervalView(plan: activeIntervalSession.plan, kind: activeIntervalSession.kind) {
                    self.activeIntervalSession = nil
                }
            } else if let activeCardioKind, let activeCardioSpec {
                WatchCardioSessionView(kind: activeCardioKind, spec: activeCardioSpec) {
                    self.activeCardioKind = nil
                    self.activeCardioSpec = nil
                }
            } else {
                launcher
            }
        }
        .task { watchManager.applyCustomExercisesInBackground(container: context.container) }
        .onChange(of: watchManager.customExercisesUpdatedAt) { _, _ in
            // Stored in the background; skipped when the phone replays an unchanged list.
            watchManager.applyCustomExercisesInBackground(container: context.container)
        }
        .onChange(of: watchManager.activeSwimSpec, initial: true) { _, spec in
            guard let spec, activeCardioKind == nil, watchManager.phoneRequestID == nil,
                  watchManager.phoneLaunchPendingSince == nil else { return }
            activeCardioKind = .swim
            activeCardioSpec = spec
        }
        .onOpenURL { launchRequests.handle($0) }
        .onChange(of: launchRequests.pendingStart, initial: true) { _, style in
            guard style != nil, !watchManager.isActive, activeIntervalSession == nil, activeCardioKind == nil,
                  let style = launchRequests.consumeStart() else { return }
            handleStartRequest(style)
        }
        .sheet(isPresented: Binding(get: { plannedSwimSpec != nil }, set: { if !$0 { plannedSwimSpec = nil } })) {
            if let planned = plannedSwimSpec {
                WatchCardioSetupView(kind: .swim, location: $cardioLocation, lapLength: $cardioLapLength,
                                     unit: watchAppSettings.unit,
                                     plannedDurationSeconds: planned.plannedDurationSeconds,
                                     targetZone: planned.targetZone) { spec in
                    startConfiguredCardio(.swim, spec: spec)
                    plannedSwimSpec = nil
                }
            }
        }
        .alert("Swim could not start", isPresented: Binding(get: { cardioStartError != nil }, set: { if !$0 { cardioStartError = nil } })) {
            Button("OK", role: .cancel) { cardioStartError = nil }
        } message: { Text(cardioStartError ?? "") }
        .accessibilityIdentifier("watch.root")
    }

    /// D-W5 / A2 — Start from the Action Button or the Smart Stack: an unfinished workout resumes
    /// first (nothing is ever silently discarded), then today's plan, then a quick lift.
    private func handleStartRequest(_ style: CladironWorkoutStyle) {
        if let resume = resumableStrengthSession {
            resumingSession = resume
            return
        }
        if style == .todaysPlan {
            switch WatchTodayRecommendations.startDecision(for: watchManager.todayPlan) {
            case .launch(let row):
                startRecommendation(row)
                return
            case .choose:
                // Both are planned: Today shows both rows; the user picks one deliberately.
                return
            case .none:
                break
            }
        }
        startingQuickLift = true
    }

    /// Watch redesign §5 T1–T4 — Today: one hero (resume / today's plan / rest day), two tiles
    /// (Lift · Cardio), settings behind ⚙︎. Double Tap = the hero's primary action.
    private var launcher: some View {
        NavigationStack {
            // Page 1 is Today; swipe left for This Week (HIG: peer pages in a page-style TabView).
            TabView {
                launcherList
                WatchWeekView(summary: watchManager.weekSummary, overlays: watchManager.weekLocalOverlays, currentWeekKey: WatchWorkoutManager.currentWeekKey())
                WatchMyWorkoutsView(plan: watchManager.todayPlan,
                                    pendingCardioCompletions: watchManager.pendingCardioCompletions,
                                    cardioHistoryRevision: watchManager.cardioHistoryRevision,
                                    distanceUnit: watchAppSettings.distanceUnit)
            }
            .tabViewStyle(.page)
            .navigationTitle("Cladiron")
            .task(id: sessionOwnership) {
                if case .endNow(let startedAt) = sessionOwnership {
                    watchManager.endAbandonedSession(startedAt: startedAt)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { WatchSettingsView() } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(Text("Settings"))
                        .accessibilityIdentifier("watch.settings")
                }
            }
            .navigationDestination(isPresented: Binding(get: { plannedStrengthSession != nil },
                                                        set: { if !$0 { plannedStrengthSession = nil } })) {
                plannedStrengthDestination
            }
            .navigationDestination(item: $resumingSession) { session in WatchStrengthView(resuming: session) }
            .navigationDestination(isPresented: $startingQuickLift) { WatchStrengthStartView() }
            .navigationDestination(isPresented: $showingWorkoutChoice) {
                WatchWorkoutChoiceView(
                    onStrength: { showingWorkoutChoice = false; startingQuickLift = true },
                    onCardio: { showingWorkoutChoice = false; showingCardio = true })
            }
            .navigationDestination(isPresented: $showingCardio) {
                WatchCardioPickerView(types: cardioTypes) { ct in AnyView(cardioSetupView(for: ct)) }
            }
            .alert("Discard this workout?", isPresented: $confirmDiscardResume) {
                Button("Discard", role: .destructive) {
                    if let resume = resumableStrengthSession { discardResumable(resume) }
                }
                .accessibilityIdentifier("watch.resumeStrength.delete")
                Button("Keep", role: .cancel) {}
            } message: {
                Text("The sets logged on this watch are removed.")
            }
        }
    }

    private var launcherList: some View {
        List {
            if needsHealthAccess {
                Button {
                    Task { _ = await watchManager.requestWorkoutAuthorization() }
                } label: {
                    Label("Health access needed. Tap to enable.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(WatchTone.attention)
                }
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("healthWarningRow")
            }
            WatchSessionOwnershipCard(verdict: sessionOwnership)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            // A workout explicitly sent from the phone takes precedence over coaching content.
            WatchSentWorkoutsSection(onStartCardio: startPlannedCardio)
            heroCard
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            if presentation.showsQuickStartTiles {
                WatchQuickStartTiles(
                    onLift: { startingQuickLift = true },
                    onCardio: { showingCardio = true })
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.plain)
    }

    private var presentation: WatchTodayHomePresentation { WatchTodayHomePresentation(hero: hero) }

    private func startRecommendation(_ row: WatchTodayRecommendations.Row) {
        switch row.modality {
        case .strength: plannedStrengthSession = row.session
        case .cardio: startPlannedCardio(row.session)
        }
    }

    @ViewBuilder
    private var heroCard: some View {
        let rows = WatchTodayRecommendations.visibleRows(for: watchManager.todayPlan,
                                                         hasResume: resumableStrengthSession != nil)
        if rows.isEmpty {
            heroContent
        } else {
            VStack(spacing: 6) {
                ForEach(rows) { row in WatchRecommendationRow(row: row) { startRecommendation(row) } }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("watch.todayHero")
        }
    }


    @ViewBuilder
    private var heroContent: some View {
        switch hero {
        case .resume(let title, let detail, let startedAt):
            heroContainer(colors: [Color(red: 0.35, green: 0.23, blue: 0.06), Color(red: 0.12, green: 0.08, blue: 0.02)]) {
                Text("Unfinished · \(startedAt, style: .relative) ago").font(.caption2.weight(.bold)).foregroundStyle(WatchTone.gold)
                Text(title).font(.headline)
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 6) {
                    Button("Resume") { resumingSession = resumableStrengthSession }
                        .buttonStyle(WatchPillStyle(kind: .light, small: true))
                        .handGestureShortcut(.primaryAction)
                        .accessibilityIdentifier("watch.resumeStrength")
                    Button("Discard…") { confirmDiscardResume = true }
                        .buttonStyle(WatchPillStyle(kind: .secondary, small: true))
                }
            }
        case .planned(_, let title, let exercises, let minutes, let advice):
            heroContainer(colors: [Color(red: 0.08, green: 0.35, blue: 0.2), Color(red: 0.04, green: 0.12, blue: 0.08)]) {
                Text("Today · \(title)").font(.caption2.weight(.bold)).foregroundStyle(WatchTone.accent)
                Text(exercises.prefix(5).joined(separator: " · ")).font(.footnote.weight(.semibold)).lineLimit(3)
                if let minutes {
                    (Text("\(exercises.count) exercises") + Text(verbatim: " · ~") + Text("\(minutes) min")).font(.caption2).foregroundStyle(.secondary)
                }
                if let advice { WatchCoachLineView(line: advice) }
                Button { plannedStrengthSession = watchManager.todayPlan?.sessions.first(where: \.isStrength) } label: { Label("Start", systemImage: "play.fill") }
                    .buttonStyle(WatchPillStyle(kind: .primary))
                    .handGestureShortcut(.primaryAction)
                    .accessibilityIdentifier("watch.startPlanned")
            }
        case .plannedCardio(let sessionID, let title, let detail, let advice):
            heroContainer(colors: [Color(red: 0.05, green: 0.25, blue: 0.3), Color(red: 0.02, green: 0.08, blue: 0.1)]) {
                Text("Today").font(.caption2.weight(.bold)).foregroundStyle(.teal)
                Text(title).font(.headline)
                if !detail.isEmpty { Text(detail).font(.caption2).foregroundStyle(.secondary) }
                if let advice { WatchCoachLineView(line: advice) }
                Button {
                    if let session = watchManager.todayPlan?.sessions.first(where: { $0.id == sessionID }) {
                        startPlannedCardio(session)
                    }
                } label: { Label("Start", systemImage: "play.fill") }
                    .buttonStyle(WatchPillStyle(kind: .primary))
                    .handGestureShortcut(.primaryAction)
                    .accessibilityIdentifier("watch.startPlannedCardio")
            }
        case .restDay(let advice):
            heroContainer(gradient: WatchTone.restGradient) {
                Label("Rest day", systemImage: "bed.double.fill").font(.headline)
                if let advice { WatchCoachLineView(line: advice) }
                Text("Recovery supports progress.").font(.caption2).foregroundStyle(.secondary)
                Button("Start another workout") { showingWorkoutChoice = true }
                    .buttonStyle(WatchPillStyle(kind: .secondary, small: true))
                    .accessibilityHint(Text("Choose strength or cardio"))
                    .accessibilityIdentifier("watch.rest.startAnother")
            }
        case .unplanned:
            WatchReadyCard(
                syncReminder: presentation.syncReminder,
                onStrength: { startingQuickLift = true },
                onCardio: { showingCardio = true })
        }
    }

    private func heroContainer<Content: View>(colors: [Color], @ViewBuilder _ content: () -> Content) -> some View {
        heroContainer(gradient: LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), content)
    }

    private func heroContainer<Content: View>(gradient: LinearGradient, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4, content: content)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("watch.todayHero")
    }

    @ViewBuilder
    private var plannedStrengthDestination: some View {
        if let session = plannedStrengthSession {
            WatchStrengthView(
                title: session.label.isEmpty ? "Strength" : session.label,
                plannedExerciseNames: session.exerciseNames,
                repLadder: session.repLadder,
                planPayload: session.planPayload)
        }
    }

    var resumableStrengthSession: WorkoutSession? {
        resumableSessions.first(where: \.isResumable)
    }

    /// Deletes an abandoned watch-only session in place and tells the phone to
    /// drop its copy, without opening the workout.
    private func discardResumable(_ session: WorkoutSession) {
        WatchHaptics.tap()
        // The discarded lift's session must stop too, or it keeps recording with nothing to resume.
        if watchManager.isActive, watchManager.workoutType == "strength", watchManager.phoneRequestID == nil {
            watchManager.stopWorkout(save: false)
        }
        guard let payload = WatchResumableSession.discard(session, in: context) else { return }
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(payload)
    }

    private func startPlannedCardio(_ session: WatchSync.TodayPlan.Session) {
        let ct = cardioType(from: session.cardioType)
        if ct == .hiit || ct == .boxing {
            let richCardio = session.planPayload?.cardio.first
            if let data = richCardio?.intervalPlanData,
               let plan = try? JSONDecoder().decode(IntervalPlan.self, from: data) {
                activeIntervalSession = ActiveIntervalSession(plan: plan, kind: ct.displayName)
            } else {
                let model = intervalSetupModel(kind: ct.displayName)
                activeIntervalSession = ActiveIntervalSession(plan: model.intervalPlan(), kind: ct.displayName)
            }
        } else {
            let richCardio = session.planPayload?.cardio.first
            let duration = richCardio?.durationSeconds ?? session.durationMinutes.map { $0 * 60 }
            let zone = richCardio?.targetZone ?? session.zone
            let spec = WorkoutConfigurationSpec(
                for: ct.rawValue,
                plannedDurationSeconds: duration,
                targetZone: zone)
            if ct == .swim {
                plannedSwimSpec = spec
            } else {
                startConfiguredCardio(ct, spec: spec)
            }
        }
    }

    @ViewBuilder
    private func cardioSetupView(for ct: CardioType) -> some View {
        let kind = ct.toCardioKind()
        if ct == .hiit || ct == .boxing {
            WatchIntervalSetupView(kind: ct.displayName, model: intervalSetupModel(kind: ct.displayName)) { plan in
                activeIntervalSession = ActiveIntervalSession(plan: plan, kind: ct.displayName)
            }
        } else {
            WatchCardioSetupView(kind: kind, location: $cardioLocation, lapLength: $cardioLapLength, unit: watchAppSettings.unit) { spec in
                startConfiguredCardio(ct, spec: spec)
            }
        }
    }

    private func startConfiguredCardio(_ type: CardioType, spec: WorkoutConfigurationSpec) {
        let owns = watchManager.beginCardioWorkout(type: type.rawValue, spec: spec)
        guard type != .swim || owns else {
            cardioStartError = String(localized: "Another workout is already using the watch. Finish it before starting a swim so automatic distance and lap tracking can start.")
            return
        }
        activeCardioKind = spec.kind
        activeCardioSpec = spec
    }

}
