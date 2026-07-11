import SwiftUI

struct RootTabView: View {
    enum Tab: Hashable { case workout, tests, progress }
    @Environment(AppSettings.self) private var settings
    @State private var selection: Tab = .workout
    @State private var showSplash = true

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
    }
}
