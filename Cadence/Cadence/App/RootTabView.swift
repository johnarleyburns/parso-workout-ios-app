import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct RootTabView: View {
    enum Tab: Hashable { case home, thisWeek, progress, settings }
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @Environment(ActiveWorkoutModel.self) private var active
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Tab = .home
    @State private var showSplash = true
    @State private var watchSyncToast: WatchSyncToast?
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
            .fullScreenCover(isPresented: Binding(
                get: { !settings.hasCompletedOnboarding },
                set: { presented in if !presented { settings.hasCompletedOnboarding = true } }
            )) {
                OnboardingView()
            }

            if showSplash && settings.hasCompletedOnboarding {
                SplashView(isPresented: $showSplash)
                    .zIndex(10)
                    .transition(.opacity)
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
        // The live workout + its finish summary share ONE root-level cover
        // (launch-blockers Phase 1b). A cover — not a NavigationStack push — so
        // lock/unlock can never pop the session (iOS 17 NavigationStack drops
        // non-Codable path values on background). Ending a workout swaps the
        // surface identity `.session` → `.summary` in place: no Home flash.
        .fullScreenCover(item: $active.presentedSurface) { surface in
            switch surface {
            case .session(let session):
                NavigationStack { SessionView(session: session) }
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
            if active.isActive {
                WorkoutLiveActivityCoordinator.shared.update(
                    elapsedSeconds: Int(active.clock.elapsed()),
                    status: active.isPaused ? "Paused" : "Active",
                    isPaused: active.isPaused,
                    restEndsAt: active.restEndsAt,
                    nextExercise: active.nextExercise)
            }
        }
        .onChange(of: active.isActive) { _, isActive in
            if isActive, let session = active.strengthSession {
                WorkoutLiveActivityCoordinator.shared.start(
                    title: session.title.isEmpty ? "Workout" : session.title,
                    restEndsAt: active.restEndsAt,
                    nextExercise: active.nextExercise)
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
            // Clear the legacy weekly Today-plan projection from older builds.
            // Current Watch/widget projections are populated only from explicit
            // one-off scheduled workouts.
            model.clearWatchTodayPlan()
            // The training log syncs live via SwiftData↔CloudKit (private DB);
            // there is nothing to restore or upload here — SwiftData mirrors the
            // store automatically on launch and as changes happen.
        }
        .onChange(of: scenePhase) { _, phase in
            active.writeHeartbeat()
            guard phase == .active else { return }
            model.pushSettingsContext()
        }
        .onChange(of: settings.unit) { _, _ in model.pushSettingsContext() }
        .onChange(of: settings.intervalColorBlind) { _, _ in model.pushSettingsContext() }
        .onChange(of: settings.restSeconds) { _, _ in model.pushSettingsContext() }
        .onChange(of: settings.warmupMinutes) { _, _ in model.pushSettingsContext() }
        .onChange(of: settings.cooldownMinutes) { _, _ in model.pushSettingsContext() }
        .onChange(of: settings.workoutSounds) { _, _ in model.pushSettingsContext() }
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
                    TrainingProgressView()
                }
                SwiftUI.Tab("Settings", systemImage: "gearshape", value: .settings) {
                    NavigationStack { SettingsView() }
                }
            }
            .modifier(MinimizeTabBarOnScrollDown())
        } else {
            TabView(selection: $selection) {
                HomeView().tabItem { Label("Today", systemImage: "house") }.tag(Tab.home)
                ThisWeekView().tabItem { Label("This Week", systemImage: "calendar") }.tag(Tab.thisWeek)
                TrainingProgressView().tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }.tag(Tab.progress)
                NavigationStack { SettingsView() }
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(Tab.settings)
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

    private func showWatchSyncToast(for state: WatchSync.Status) {
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
            .lineLimit(1)
            .minimumScaleFactor(0.75)
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
