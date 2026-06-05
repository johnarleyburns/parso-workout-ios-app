import SwiftUI
import CadenceCore

/// Five-tab shell matching the design mockups: Today, Train, Cardio, Trends,
/// Settings.
struct RootTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .accessibilityIdentifier("tab.today")
            TrainView()
                .tabItem { Label("Train", systemImage: "dumbbell") }
                .accessibilityIdentifier("tab.train")
            CardioView()
                .tabItem { Label("Cardio", systemImage: "figure.run") }
                .accessibilityIdentifier("tab.cardio")
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
                .accessibilityIdentifier("tab.trends")
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .accessibilityIdentifier("tab.settings")
        }
    }
}
