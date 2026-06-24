import SwiftUI

struct RootTabView: View {
    enum Tab: Hashable { case workout, tests, progress }
    @Environment(AppSettings.self) private var settings
    @State private var selection: Tab = .workout
    @State private var showSplash = true

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
