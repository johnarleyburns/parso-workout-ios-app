import SwiftUI

struct RootTabView: View {
    enum Tab: Hashable { case workout, plan, library }
    @State private var selection: Tab = .workout

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Workout", systemImage: "figure.strengthtraining.traditional") }
                .tag(Tab.workout)
                .accessibilityIdentifier("tab.workout")

            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(Tab.plan)
                .accessibilityIdentifier("tab.plan")

            LibraryView(switchToWorkout: { selection = .workout })
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(Tab.library)
                .accessibilityIdentifier("tab.library")
        }
    }
}
