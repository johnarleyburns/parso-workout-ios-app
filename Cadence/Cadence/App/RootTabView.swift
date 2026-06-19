import SwiftUI

struct RootTabView: View {
    enum Tab: Hashable { case workout, tests, progress }
    @State private var selection: Tab = .workout

    var body: some View {
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
    }
}
