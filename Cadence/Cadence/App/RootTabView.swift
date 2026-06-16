import SwiftUI

/// The app's root bottom tab bar (strength-pivot P3). Three tabs:
/// - **Workout** — the existing Home dashboard (Coach card + start/log + history).
/// - **Plan** — placeholder for goals, calendar, and favorited exercises (later phase).
/// - **Library** — placeholder for the full exercise library, routines, and the
///   studies behind the coaching (later phase).
///
/// In P3 only Workout has real content; Plan and Library are intentional
/// "coming soon" scaffolds so the navigation shell is in place.
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

            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(Tab.library)
                .accessibilityIdentifier("tab.library")
        }
    }
}
