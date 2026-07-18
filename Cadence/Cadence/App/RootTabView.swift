import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct RootTabView: View {
    enum Tab: Hashable { case workout, tests, progress }
    @Environment(AppSettings.self) private var settings
    @Environment(CloudBackupService.self) private var backup
    @Environment(AppModel.self) private var model
    @Environment(ActiveWorkoutModel.self) private var active
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Tab = .workout
    @State private var showSplash = true
    @State private var offerRestore: RemoteBackupMeta?
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
                        Label("Workout", systemImage: "figure.strengthtraining.traditional")
                            .accessibilityIdentifier("tab.workout")
                    }
                    .tag(Tab.workout)

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
                WorkoutSummaryView(data: finished.data,
                                   onDone: { active.finishedSummary = nil })
            }
        }
        // Keep the screen awake while a workout is active in any navigation
        // state — presented or minimized — except a paused-and-minimized one
        // (e.g. crash-recovered onto Home), which shouldn't burn the screen.
        .keepAwake(active.isActive && !(active.isPaused && active.presentedSurface == nil))
        .onReceive(heartbeatTimer) { _ in active.writeHeartbeat() }
        .task {
            // Crash/upgrade recovery FIRST (launch-blockers Phase 1e): re-adopt
            // an in-progress workout paused; Home shows the Resume card. A
            // workout is never auto-ended or discarded, no matter how stale.
            recoverActiveSessionIfNeeded()
            // On launch: if the local store is empty and a remote backup exists,
            // auto-restore (fresh install). If local data is present, ask first —
            // never silently clobber. Guarded by BackupPolicy in the service.
            guard settings.iCloudBackupEnabled else { return }
            switch await backup.restoreDecision() {
            case .autoRestore:
                try? await backup.restore(settings: settings)
            case .offerRestore(let meta):
                offerRestore = meta
            case .none:
                break
            }
            // Opportunistic backup (no-ops when not due).
            await backup.backUpIfNeeded(settings: settings)
        }
        .onChange(of: scenePhase) { _, phase in
            active.writeHeartbeat()
            guard phase == .active else { return }
            if settings.iCloudBackupEnabled { Task { await backup.backUpIfNeeded(settings: settings) } }
            model.pushSettingsContext()
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutHistoryChanged)) { _ in
            // Mark the store dirty so BackupPolicy schedules the next backup.
            settings.lastLocalChangeAt = Date()
        }
        .alert("Restore from iCloud?", isPresented: Binding(
            get: { offerRestore != nil },
            set: { if !$0 { offerRestore = nil } }
        )) {
            Button("Restore") {
                let s = settings
                offerRestore = nil
                Task { try? await backup.restore(settings: s) }
            }
            Button("Not Now", role: .cancel) { offerRestore = nil }
        } message: {
            if let meta = offerRestore {
                Text("An iCloud backup from \(meta.createdAt.formatted(date: .abbreviated, time: .shortened)) with \(meta.sessionCount) workout\(meta.sessionCount == 1 ? "" : "s") is available. Restoring merges it into your current data — nothing is deleted.")
            }
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
}
