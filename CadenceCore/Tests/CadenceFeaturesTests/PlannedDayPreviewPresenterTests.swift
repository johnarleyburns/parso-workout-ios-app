import XCTest
import CadenceCore
import CadenceFeatures

final class PlannedDayPreviewPresenterTests: XCTestCase {
    func testRestDayFooterUsesRestCopy() {
        let day = day([
            PlannedSession(id: "rest", kind: .rest, label: "Rest", isHard: false, isRest: true)
        ])

        XCTAssertEqual(
            PlannedDayPreviewPresenter.footerText(for: day),
            "This is a rest day, enjoy it, you earned it!"
        )
    }

    func testPlannedTrainingDayKeepsStartFromWorkoutCopy() {
        let day = day([
            PlannedSession(id: "strength", kind: .strength, label: "Strength", isHard: true, isRest: false)
        ])

        XCTAssertEqual(
            PlannedDayPreviewPresenter.footerText(for: day),
            "This is a planned day. Start it from the Workout tab when it's today."
        )
    }

    func testStrengthPrescriptionUsesConfiguredSets() {
        XCTAssertEqual(
            PlannedDayPreviewPresenter.strengthPrescription(goal: .hypertrophy, sets: 4),
            "4 sets · 12-10-8-6 reps · ~1 RIR"
        )
    }

    private func day(_ sessions: [PlannedSession]) -> WeeklyPlan.DayOutline {
        WeeklyPlan.DayOutline(
            date: Date(timeIntervalSince1970: 1_750_000_000),
            label: sessions.map(\.label).joined(separator: " · "),
            sessions: sessions,
            isFuture: true
        )
    }
}
