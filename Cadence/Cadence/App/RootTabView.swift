import SwiftUI
import CadenceCore
import CadenceFeatures

struct RootTabView: View {
    enum Tab: Hashable { case workout, tests, progress }
    @Environment(AppSettings.self) private var settings
    @Environment(CloudBackupService.self) private var backup
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Tab = .workout
    @State private var showSplash = true
    @State private var offerRestore: RemoteBackupMeta?

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
        ZStack {
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
        .task {
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
            guard phase == .active, settings.iCloudBackupEnabled else { return }
            Task { await backup.backUpIfNeeded(settings: settings) }
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
}
