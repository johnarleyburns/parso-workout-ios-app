import SwiftUI
import SwiftData
import WatchConnectivity
import CadenceCore
import CadenceFeatures

struct WatchRootView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager
    @Environment(AppSettings.self) private var watchAppSettings
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
    @State private var startingPlanned = false
    @State private var resumingSession: WorkoutSession?
    @State private var confirmDiscardResume = false
    @State private var startingQuickLift = false
    @State private var showingCardio = false
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
        .onChange(of: watchManager.customExercisesUpdatedAt) { _, _ in
            // Stored on a background context, and skipped entirely when the
            // phone replays an unchanged list (it does on every activation).
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
            if watchManager.todayPlan?.sessions.contains(where: \.isStrength) == true {
                startingPlanned = true
                return
            }
            if let cardio = watchManager.todayPlan?.sessions.first(where: { !$0.isStrength }) {
                startPlannedCardio(cardio)
                return
            }
        }
        startingQuickLift = true
    }

    /// Watch redesign §5 T1–T4 — Today: one hero (resume / today's plan / rest day), two tiles
    /// (Quick lift · Cardio), settings behind ⚙︎. Double Tap = the hero's primary action.
    private var launcher: some View {
        NavigationStack {
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
                heroCard
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                // Two tiles in one row: plain Buttons with their own destinations, because a List row
                // with two NavigationLinks activates as one (tapping Quick lift opened Cardio).
                HStack(spacing: 6) {
                    Button { startingQuickLift = true } label: {
                        tile(title: "Quick lift", systemImage: "dumbbell.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watch.startStrength")
                    Button { showingCardio = true } label: {
                        tile(title: "Cardio", systemImage: "figure.run")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watch.cardio")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .listStyle(.plain)
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
            .navigationDestination(isPresented: $startingPlanned) { plannedStrengthDestination }
            .navigationDestination(item: $resumingSession) { session in WatchStrengthView(resuming: session) }
            .navigationDestination(isPresented: $startingQuickLift) { WatchStrengthStartView() }
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

    private var sessionOwnership: WatchSessionOwnership.Verdict {
        watchManager.sessionOwnership(hasResumableStrength: resumableStrengthSession != nil)
    }

    private var needsHealthAccess: Bool { !watchManager.workoutShareAuthorized && !watchManager.isActive }

    private var hero: WatchTodayHero {
        let resume = resumableStrengthSession.map { session in
            WatchTodayHeroBuilder.ResumeInput(
                title: session.title.isEmpty ? String(localized: "Workout") : session.title,
                startedAt: session.date,
                exercises: Self.loggedPerExercise(session),
                plannedSets: Dictionary(session.plannedPrescriptions.map {
                    ($0.exerciseName, $0.sets.filter { $0.kind != .warmup }.count) }, uniquingKeysWith: { a, _ in a }))
        }
        return WatchTodayHeroBuilder.make(
            resume: resume,
            plan: watchManager.todayPlan,
            synced: watchManager.lastPhoneSyncAt != nil)
    }

    private static func loggedPerExercise(_ session: WorkoutSession) -> [(name: String, sets: Int)] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for set in session.orderedSets where !set.isWarmup {
            let name = set.exercise?.name ?? ""
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        return order.map { ($0, counts[$0] ?? 0) }
    }

    @ViewBuilder
    private var heroCard: some View {
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
                Button { startingPlanned = true } label: { Label("Start", systemImage: "play.fill") }
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
            heroContainer(colors: [WatchTone.surface, WatchTone.surface]) {
                Label("Rest day", systemImage: "bed.double.fill").font(.headline)
                if let advice { WatchCoachLineView(line: advice) }
                Text("Training anyway is your call.").font(.caption2).foregroundStyle(.secondary)
            }
        case .unplanned(let synced):
            heroContainer(colors: [WatchTone.surface, WatchTone.surface]) {
                Text(synced ? "Nothing planned today" : "Open Cladiron on iPhone to sync today.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func heroContainer<Content: View>(colors: [Color], @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4, content: content)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("watch.todayHero")
    }

    private func tile(title: LocalizedStringKey, systemImage: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(height: 22, alignment: .center)
            Text(title)
                .font(.caption2.weight(.semibold))
                .frame(height: 16, alignment: .center)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .center)
        .background(RoundedRectangle(cornerRadius: 14).fill(WatchTone.surface))
    }

    @ViewBuilder
    private var plannedStrengthDestination: some View {
        if let session = watchManager.todayPlan?.sessions.first(where: \.isStrength) {
            WatchStrengthView(
                title: session.label.isEmpty ? "Strength" : session.label,
                plannedExerciseNames: session.exerciseNames,
                repLadder: session.repLadder,
                planPayload: session.planPayload)
        }
    }

    private var resumableStrengthSession: WorkoutSession? {
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

    private func intervalSetupModel(kind: String) -> IntervalSetupModel {
        let isHIITOrBoxing = kind.lowercased() == "hiit" || kind.lowercased() == "boxing"
        let syncedWarmup = isHIITOrBoxing ? nil : (watchManager.lastPhoneSyncAt == nil ? nil : watchAppSettings.warmupMinutes * 60)
        let syncedCooldown = isHIITOrBoxing ? nil : (watchManager.lastPhoneSyncAt == nil ? nil : watchAppSettings.cooldownMinutes * 60)
        return IntervalSetupModel(kind: kind, warmupSeconds: syncedWarmup, cooldownSeconds: syncedCooldown)
    }
}
