import SwiftUI
import Combine
import SwiftData
import CadenceCore
import CadenceFeatures

struct RootTabView: View {
    enum Tab: Hashable { case home, thisWeek, progress, settings, search }
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @Environment(ActiveWorkoutModel.self) private var active
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Tab = .home
    @State private var watchSyncToast: WatchSyncToast?
    @State private var draftSheetPresented = false
    /// UI-test seam backing the `-uiTestWatchStop` counter: `AppModel` writes
    /// each `stopWatchWorkout()` call to this UserDefaults key, and the hidden
    /// element below surfaces the running total to the iPhone smoke test.
    @AppStorage("uitest.watchStopCount") private var uiTestWatchStopCount = 0
    /// Liveness heartbeat for crash/upgrade recovery (launch-blockers Phase 1e).
    /// Root-level so it keeps beating while the workout is minimized.
    private let heartbeatTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var active = active
        return ZStack {
            nativeTabs
                .safeAreaInset(edge: .top, spacing: 0) {
                    if selection != .search {
                        PlanningDraftEntryStrip { draftSheetPresented = true }
                    }
                }

            // Explicit Watch action results use one non-layout-affecting host.
            // Automatic CloudKit restore state stays in Settings/diagnostics so
            // it never shifts the Today dashboard during launch.
            if watchSyncToast != nil {
                GeometryReader { proxy in
                    VStack(spacing: 8) {
                        if let watchSyncToast {
                            WatchSyncToastView(toast: watchSyncToast)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, proxy.safeAreaInsets.top + 52)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .zIndex(20)
            }

            if model.isUITestMode {
                Text("\(uiTestWatchStopCount)")
                    .accessibilityIdentifier("uitest.watchStopCount")
                    .frame(width: 1, height: 1)
                    .opacity(0)
                    .allowsHitTesting(false)
            }
        }
        .environment(\.rootTabSelection, $selection)
        .sheet(isPresented: $draftSheetPresented) {
            NavigationStack {
                WorkoutDraftView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { draftSheetPresented = false }
                        }
                    }
            }
            .environment(\.rootTabSelection, $selection)
        }
        // The live workout + its finish summary share ONE root-level cover
        // (launch-blockers Phase 1b). A cover — not a NavigationStack push — so
        // lock/unlock can never pop the session (iOS 17 NavigationStack drops
        // non-Codable path values on background). Ending a workout swaps the
        // surface identity `.session` → `.summary` in place: no Home flash.
        .fullScreenCover(item: $active.presentedSurface) { surface in
            switch surface {
            case .session(let session):
                AdaptiveSessionRoot(session: session)
            case .summary(let finished):
                // Tapping an exercise expands it read-only in place (field test
                // 2026-08-18 #1, decision D7). Editing what was just logged stays
                // reachable through the toolbar's Edit, which reopens the session
                // — the escape hatch NFR-8 requires.
                let reviewSession = finished.session
                WorkoutSummaryView(data: finished.data,
                                   onEdit: reviewSession.map { session in
                                       {
                                           active.finishedSummary = nil
                                           active.presentedSurface = .session(session)
                                       }
                                   },
                                   onDone: { active.finishedSummary = nil })
            }
        }
        // Keep the screen awake while a workout is active in any navigation
        // state — presented or minimized — except a paused-and-minimized one
        // (e.g. crash-recovered onto Home), which shouldn't burn the screen.
        .keepAwake(active.isActive && !(active.isPaused && active.presentedSurface == nil))
        .onReceive(heartbeatTimer) { _ in
            active.writeHeartbeat()
            if let request = CadencePlatformRequestStore.consumeLiveActivityRequest() {
                NotificationCenter.default.post(name: .cadenceLiveActivityActionRequested,
                                                object: request)
            }
            if active.isActive {
                WorkoutLiveActivityCoordinator.shared.update(
                    elapsedSeconds: Int(active.clock.elapsed()),
                    status: active.isPaused ? String(localized: "Paused") : String(localized: "Active"),
                    isPaused: active.isPaused,
                    restEndsAt: active.restEndsAt,
                    nextExercise: active.nextExercise,
                    nextSetSummary: active.nextSetSummary,
                    nextSetToken: active.nextSetToken)
            } else {
                // Heartbeat backstop: no active workout means no Live Activity.
                WorkoutLiveActivityCoordinator.shared.reconcile(
                    workoutIsActive: active.isActive, hasStrengthSession: active.strengthSession != nil)
            }
        }
        .onChange(of: active.isActive) { _, isActive in
            // Workout start/end boundary: propagate summary state (bounded by the tracker).
            model.pushSettingsContext(reason: .workoutBoundary)
            if isActive, let session = active.strengthSession {
                WorkoutLiveActivityCoordinator.shared.start(
                    title: session.title.isEmpty ? String(localized: "Workout") : session.title,
                    restEndsAt: active.restEndsAt,
                    nextExercise: active.nextExercise,
                    nextSetSummary: active.nextSetSummary,
                    nextSetToken: active.nextSetToken)
            } else {
                WorkoutLiveActivityCoordinator.shared.end()
            }
        }
        .task {
            // Crash/upgrade recovery FIRST (launch-blockers Phase 1e): re-adopt
            // an in-progress workout paused and return straight to its session
            // surface. A workout is never auto-ended or discarded, no matter
            // how stale. Manual minimization remains a deliberate path to Home.
            recoverActiveSessionIfNeeded()
            // End any Live Activity orphaned by a previous launch when no
            // workout is running (issue #74).
            WorkoutLiveActivityCoordinator.shared.reconcile(workoutIsActive: active.isActive)
            // Recovery can make the workout active before this view's
            // `.onChange` observer is installed. Reconcile once after launch
            // so a recovered workout always gets its Live Activity.
            if active.isActive, let session = active.strengthSession {
                WorkoutLiveActivityCoordinator.shared.start(
                    title: session.title.isEmpty ? String(localized: "Workout") : session.title,
                    restEndsAt: active.restEndsAt,
                    nextExercise: active.nextExercise,
                    nextSetSummary: active.nextSetSummary,
                    nextSetToken: active.nextSetToken)
            } else {
                // Launch cleanup: end any activity orphaned by a prior process.
                WorkoutLiveActivityCoordinator.shared.reconcile(
                    workoutIsActive: active.isActive, hasStrengthSession: active.strengthSession != nil)
            }
            // The training log syncs live via SwiftData↔CloudKit (private DB);
            // there is nothing to restore or upload here — SwiftData mirrors the
            // store automatically on launch and as changes happen.
        }
        .onChange(of: scenePhase) { _, phase in
            active.writeHeartbeat()
            // End any Live Activity that outlived its workout (e.g. a finish
            // while suspended could lose the async end) on every transition.
            if !active.isActive {
                WorkoutLiveActivityCoordinator.shared.reconcile(
                    workoutIsActive: false, hasStrengthSession: false)
            }
            guard phase == .active else { return }
            model.pushSettingsContext(reason: .activation)
            if let request = CadencePlatformRequestStore.consumeLiveActivityRequest() {
                NotificationCenter.default.post(name: .cadenceLiveActivityActionRequested,
                                                object: request)
            }
            if CadencePlatformRequestStore.consumeQuickTalk() {
                NotificationCenter.default.post(name: .cadenceQuickTalkRequested, object: nil)
            }
        }
        .modifier(WatchSettingsContextSync(settings: settings, model: model))
        .onChange(of: model.watchSyncState) { _, state in
            showWatchSyncToast(for: state)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cadenceShowThisWeek)) { _ in
            selection = .thisWeek
        }
        .onOpenURL { url in
            guard url.scheme == "cladiron" else { return }
            if url.host == "this-week" || url.path == "/this-week" {
                selection = .thisWeek
            } else if url.host == "workout" || url.path == "/workout" {
                selection = .home
                CadencePlatformRequestStore.requestStartWorkout()
                NotificationCenter.default.post(name: .cadenceStartTodaysWorkout, object: nil)
            } else {
                // Old weekly-plan deep links remain safe after the Plan tab is
                // retired: one-off scheduled workouts are reached from Home.
                selection = .home
            }
        }
        .onContinueUserActivity(CadenceHandoff.planActivityType) { _ in
            selection = .home
        }
    }

    @ViewBuilder
    private var nativeTabs: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $selection) {
                SwiftUI.Tab("Today", systemImage: "house", value: .home) { HomeView() }
                SwiftUI.Tab("This Week", systemImage: "calendar", value: .thisWeek) { ThisWeekView() }
                SwiftUI.Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: .progress) {
                    AdaptiveProgressRoot()
                }
                SwiftUI.Tab("Find", systemImage: "magnifyingglass", value: .search) { FindExercisesView() }
            }
            .modifier(MinimizeTabBarOnScrollDown())
            .modifier(LiveWorkoutTabAccessory(active: active))
        } else {
            TabView(selection: $selection) {
                HomeView().tabItem { Label("Today", systemImage: "house") }.tag(Tab.home)
                ThisWeekView().tabItem { Label("This Week", systemImage: "calendar") }.tag(Tab.thisWeek)
                AdaptiveProgressRoot().tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }.tag(Tab.progress)
            }
        }
    }

    /// Re-adopts an in-progress session after a crash, force-quit, jetsam, or
    /// app upgrade (launch-blockers Phase 1e). The session is adopted PAUSED
    /// (`.auto`), immediately presented, and the dead gap is excluded from the
    /// clock via the heartbeat.
    private func recoverActiveSessionIfNeeded() {
        guard active.strengthSession == nil else { return }
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate {
                $0.endedAt == nil && $0.deletedAt == nil && !$0.isLogged
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        guard let candidate = ActiveSessionRecovery.candidate(in: sessions) else {
            WorkoutHeartbeatStore.clear()
            return
        }
        active.adopt(candidate, heartbeat: WorkoutHeartbeatStore.read())
        active.present()
    }

    private func showWatchSyncToast(for state: WatchSyncState) {
        guard let text = state.toastText else { return }
        let toast = WatchSyncToast(text: text, isFailure: state.isFailure)
        withAnimation(.easeInOut(duration: 0.18)) {
            watchSyncToast = toast
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard watchSyncToast?.id == toast.id else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                watchSyncToast = nil
            }
        }
    }
}

private struct MinimizeTabBarOnScrollDown: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

private struct LiveWorkoutTabAccessory: ViewModifier {
    let active: ActiveWorkoutModel

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            let enabled = active.isActive && active.strengthSession != nil
            content.tabViewBottomAccessory(isEnabled: enabled) {
                if let session = active.strengthSession, enabled { accessory(session) }
            }
        } else {
            content.tabViewBottomAccessory {
                if active.isActive, let session = active.strengthSession { accessory(session) }
            }
        }
    }

    private func accessory(_ session: WorkoutSession) -> some View {
        Button { active.present() } label: {
            HStack(spacing: 10) {
                Image(systemName: "figure.strengthtraining.traditional")
                Text(session.title.isEmpty ? String(localized: "Workout in progress") : session.title)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up")
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab.liveWorkoutAccessory")
    }
}

/// Pushes the Watch-facing settings context whenever one of its inputs changes.
/// Split out of `RootTabView.body` so the modifier chain stays type-checkable.
private struct WatchSettingsContextSync: ViewModifier {
    let settings: AppSettings
    let model: AppModel

    func body(content: Content) -> some View {
        content
            .onChange(of: settings.unit) { _, _ in model.pushSettingsContext() }
            .onChange(of: settings.intervalColorBlind) { _, _ in model.pushSettingsContext() }
            .onChange(of: settings.restSeconds) { _, _ in model.pushSettingsContext() }
            .onChange(of: settings.warmupMinutes) { _, _ in model.pushSettingsContext() }
            .onChange(of: settings.cooldownMinutes) { _, _ in model.pushSettingsContext() }
            .onChange(of: settings.workoutSounds) { _, _ in model.pushSettingsContext() }
            .onChange(of: settings.spokenCues) { _, _ in model.pushSettingsContext() }
            // Inputs of the Watch single-exercise Suggest context.
            .onChange(of: settings.trainingGoal) { _, _ in model.pushSettingsContext() }
            .onChange(of: settings.experienceLevel) { _, _ in model.pushSettingsContext() }
            .onChange(of: settings.preferredWorkoutStyle) { _, _ in model.pushSettingsContext() }
            .onChange(of: settings.coachSchedulePreferences) { _, _ in model.pushSettingsContext() }
    }
}

private struct WatchSyncToast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isFailure: Bool
}

private struct WatchSyncToastView: View {
    let toast: WatchSyncToast

    var body: some View {
        Label(toast.text, systemImage: toast.isFailure ? "exclamationmark.triangle.fill" : "applewatch")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(toast.isFailure ? Color.red.opacity(0.45) : Color.green.opacity(0.35), lineWidth: 1)
            }
            .padding(.horizontal, 16)
            .accessibilityIdentifier("watchSync.toast")
    }
}

/// Reachable-from-anywhere entry to a non-empty Workout Draft. A top inset so
/// it never competes with the tab bar or the live-workout bottom accessory.
private struct PlanningDraftEntryStrip: View {
    @Query(filter: #Predicate<PlanningDraft> { $0.deletedAt == nil },
           sort: \PlanningDraft.updatedAt, order: .reverse) private var drafts: [PlanningDraft]
    let open: () -> Void

    private var count: Int? {
        guard let draft = drafts.first,
              let n = try? PlanningDraftCodec.decode(draft).exercises.count, n > 0 else { return nil }
        return n
    }

    var body: some View {
        if let count {
            Button(action: open) {
                HStack {
                    Image(systemName: "list.bullet.clipboard")
                    Text("Workout draft · \(PlanningDraftSummary.countText(count))").lineLimit(2)
                    Spacer()
                    Text("Continue").fontWeight(.semibold)
                }
                .font(.subheadline)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(.bar)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Continue workout draft, \(PlanningDraftSummary.countText(count))")
            .accessibilityIdentifier("planningDraft.entryStrip")
        }
    }
}
