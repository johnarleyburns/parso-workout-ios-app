import Foundation
import Testing

/// Structural guards for the compact This Week band and the five-row Start a
/// Workout list.
struct HomeCompactLayoutGuardTests {
    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test func thisWeekIsCompactWithTheLegendOnTheRight() throws {
        let content = try source("Cadence/Cadence/Features/Home/HomeView+DashboardContent.swift")
        #expect(content.contains("ThisWeekCompactPresentation.rows"))
        #expect(content.contains("compact: true"))
        let card = try source("Cadence/Cadence/Features/Home/WeeklyIntentRingsCard.swift")
        #expect(card.contains("compact"))
        #expect(card.contains("ThisWeekCompactPresentation.ringDiameter"))
    }

    @Test func startWorkoutListIsLiftThreeRecentCardioAndMore() throws {
        let controls = try source("Cadence/Cadence/Features/Home/HomeWorkoutStartControls.swift")
        #expect(controls.contains("Start a Workout"))
        #expect(!controls.contains("Start a workout"))
        #expect(controls.contains("HomeStartList.rows(recentCardio:"))
        #expect(controls.contains("HomeStartList.moreChoices()"))
        #expect(controls.contains("home.start.more"))
    }
}
