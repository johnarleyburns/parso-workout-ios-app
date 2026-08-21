import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct RootTabView: View {
    enum Tab: Hashable { case home, plan, tests, progress }
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

    init() {
        // Normalize tab-bar item layout so icons + titles sit vertically centered
        // (issue 5). Applied via appearance so it holds across iOS versions; a
        // pure SwiftUI TabView otherwise inherits the system default which read as
        // "too high" on some devices. Best-effort per the P8 decision.
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        for item in [appearance.stackedLayoutAppearance,
                     appearance.inlineLayoutAppearance,
                     appearance.compactInlineLayoutAppearance] {
            item.normal.titlePositionAdjustment = .zero
            item.selected.titlePositionAdjustment = .zero
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        @Bindable var active = active
        return ZStack {
            TabView(selection: $selection) {
                HomeView()
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                            .accessibilityIdentifier("tab.home")
                    }
                    .tag(Tab.home)

                NavigationStack { PlanningView(switchToWorkout: { selection = .home }) }
                    .tabItem {
                        Label("Plan", systemImage: "calendar")
                            .accessibilityIdentifier("tab.plan")
                    }
                    .tag(Tab.plan)

                TestsView()
                    .tabItem {
                        Label("Tests", systemImage: "checkmark.seal")
                            .accessibilityIdentifier("tab.tests")
                    }
                    .tag(Tab.tests)

                TrainingProgressView()
                    .tabItem {
                        Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                            .accessibilityIdentifier("tab.progress")
                    }
                    .tag(Tab.progress)
            }
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

            if let watchSyncToast {
                VStack(spacing: 0) {
                    WatchSyncToastView(toast: watchSyncToast)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaPadding(.top, 8)
                .zIndex(20)
                .transition(.move(edge: .top).combined(with: .opacity))
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
                    isPaused: active.isPaused)
            }
        }
        .onChange(of: active.isActive) { _, isActive in
            if isActive, let session = active.strengthSession {
                WorkoutLiveActivityCoordinator.shared.start(title: session.title.isEmpty ? "Workout" : session.title)
            } else {
                WorkoutLiveActivityCoordinator.shared.end()
            }
        }
        .task {
            // Crash/upgrade recovery FIRST (launch-blockers Phase 1e): re-adopt
            // an in-progress workout paused; Home shows the Resume card. A
            // workout is never auto-ended or discarded, no matter how stale.
            recoverActiveSessionIfNeeded()
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
    }

    /// Re-adopts an in-progress session after a crash, force-quit, jetsam, or
    /// app upgrade (launch-blockers Phase 1e). The session is adopted PAUSED
    /// (`.auto`) and not presented — Home shows the "Resume Workout" card — and
    /// the dead gap is excluded from the clock via the heartbeat.
    private func recoverActiveSessionIfNeeded() {
        guard active.strengthSession == nil else { return }
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        guard let candidate = ActiveSessionRecovery.candidate(in: sessions) else {
            WorkoutHeartbeatStore.clear()
            return
        }
        active.adopt(candidate, heartbeat: WorkoutHeartbeatStore.read())
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
