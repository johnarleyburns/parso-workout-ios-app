import Foundation
import Testing
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct PlannedDayPreviewPresenterTests {
    @Test func restDayFooterUsesRestCopy() {
        let day = day([
            PlannedSession(id: "rest", kind: .rest, label: "Rest", isHard: false, isRest: true)
        ])

        #expect(
            PlannedDayPreviewPresenter.footerText(for: day)
            == "This is a rest day, enjoy it, you earned it!"
        )
    }

    @Test func plannedTrainingDayKeepsStartFromWorkoutCopy() {
        let day = day([
            PlannedSession(id: "strength", kind: .strength, label: "Strength", isHard: true, isRest: false)
        ])

        #expect(
            PlannedDayPreviewPresenter.footerText(for: day)
            == "This is a planned day. Start it from the Workout tab when it's today."
        )
    }

    @Test func strengthPrescriptionUsesConfiguredSets() {
        #expect(
            PlannedDayPreviewPresenter.strengthPrescription(goal: .hypertrophy, sets: 4)
            == "4 sets · 12-10-8-6 reps · ~1 RIR"
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
