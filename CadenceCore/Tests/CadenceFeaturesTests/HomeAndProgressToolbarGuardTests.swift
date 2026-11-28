import Foundation
import Testing

/// Structural guards for the toolbar restructure: the Supporter badge leads,
/// one overflow menu trails, Strength/Cardio left the tab bar, the Progress
/// chips became a menu, and the Lifts method copy moved behind an info button.
struct HomeAndProgressToolbarGuardTests {
    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test func homeToolbarHasALeadingBadgeAndOneTrailingMenu() throws {
        let home = try source("Cadence/Cadence/Features/Home/HomeView+DashboardScroll.swift")
        #expect(home.contains("home.menu"))
        #expect(!home.contains("home.history"))
        #expect(!home.contains("home.settings"))
        #expect(home.contains("weekSurface?.open(.strength)"))
        #expect(home.contains("weekSurface?.open(.cardio)"))
        let leading = try #require(home.range(of: ".topBarLeading"))
        let badge = try #require(home.range(of: "supporterBadge"))
        #expect(leading.lowerBound < badge.lowerBound)
        let menu = try #require(home.range(of: "HomeMenuDestination.history"))
        #expect(badge.lowerBound < menu.lowerBound)
    }

    @Test func strengthAndCardioAreNotTabBarItems() throws {
        let root = try source("Cadence/Cadence/App/RootTabView.swift")
        #expect(!root.contains("SwiftUI.Tab(\"Strength\""))
        #expect(!root.contains("SwiftUI.Tab(\"Cardio\""))
        #expect(!root.contains("Label(\"Strength\""))
        #expect(!root.contains("Label(\"Cardio\""))
        #expect(root.contains("weekSurface.surface"))
        let surface = try source("Cadence/Cadence/App/WeekSurface.swift")
        #expect(surface.contains("case strength, cardio"))
        #expect(surface.contains("StrengthView()"))
        #expect(surface.contains("CardioWeekView()"))
    }

    @Test func progressSectionsLiveInOneMenu() throws {
        let progress = try source("Cadence/Cadence/Features/Progress/ProgressView.swift")
        #expect(!progress.contains("pickerOnly"))
        #expect(progress.contains("ProgressSectionMenuButton"))
        let menu = try source("Cadence/Cadence/Features/Progress/ProgressSectionMenuButton.swift")
        #expect(menu.contains("progress.sectionMenu"))
        #expect(menu.contains("systemImage: \"checkmark\""))
    }

    @Test func liftsHeaderIsAnIconWithMethodCopyBehindInfo() throws {
        let chart = try source("Cadence/Cadence/Features/Progress/ProgressStrengthChartView.swift")
        #expect(!chart.contains("Text(\"Charted lifts\")"))
        #expect(chart.contains("dumbbell.fill"))
        #expect(chart.contains("progress.strength.info"))
        #expect(chart.contains("Estimated 1RM trends"))
        let progress = try source("Cadence/Cadence/Features/Progress/ProgressView.swift")
        #expect(!progress.contains("Estimated 1RM trends"))
    }
}
