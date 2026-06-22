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
                    .tabItem { Label("Workout", systemImage: "figure.strengthtraining.traditional") }
                    .tag(Tab.workout)
                    .accessibilityIdentifier("tab.workout")

                TestsView()
                    .tabItem { Label("Tests", systemImage: "checkmark.seal") }
                    .tag(Tab.tests)
                    .accessibilityIdentifier("tab.tests")

                TrainingProgressView()
                    .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                    .tag(Tab.progress)
                    .accessibilityIdentifier("tab.progress")
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
