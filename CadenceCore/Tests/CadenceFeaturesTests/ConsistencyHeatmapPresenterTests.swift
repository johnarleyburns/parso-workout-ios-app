import Foundation
import Testing
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore

struct ConsistencyHeatmapPresenterTests {

    private func utcCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test func displayMapsIntensityToShade() {
        let cal = utcCalendar()
        let start = date("2026-01-01T00:00:00Z")
        let end = date("2026-01-03T00:00:00Z")
        let sessions = [
            date("2026-01-01T09:00:00Z"),
            date("2026-01-01T18:00:00Z")   // Jan 1 → 2 sessions → medium
        ]
        let d = ConsistencyHeatmapPresenter.display(sessionDates: sessions,
                                                    range: DateInterval(start: start, end: end),
                                                    calendar: cal)
        #expect(d.cells.count == 2)
        #expect(d.cells[0].shade == .medium)   // 2 sessions
        #expect(d.cells[1].shade == .none)     // rest day
    }

    @Test func summaryMentionsTrainedDaysAndStreak() {
        let cal = utcCalendar()
        let start = date("2026-01-01T00:00:00Z")
        let end = date("2026-01-04T00:00:00Z")
        let sessions = [
            date("2026-01-02T09:00:00Z"),
            date("2026-01-03T09:00:00Z")   // trailing 2-day streak
        ]
        let d = ConsistencyHeatmapPresenter.display(sessionDates: sessions,
                                                    range: DateInterval(start: start, end: end),
                                                    calendar: cal)
        #expect(d.trainedDays == 2)
        #expect(d.currentStreak == 2)
        #expect(d.summary == "2 days trained \u{00b7} 2-day streak")
    }

    @Test func summaryOmitsStreakBelowTwo() {
        let cal = utcCalendar()
        let start = date("2026-01-01T00:00:00Z")
        let end = date("2026-01-03T00:00:00Z")
        let sessions = [date("2026-01-01T09:00:00Z")]  // Jan 2 rest → no trailing streak
        let d = ConsistencyHeatmapPresenter.display(sessionDates: sessions,
                                                    range: DateInterval(start: start, end: end),
                                                    calendar: cal)
        #expect(CatalogPlural.renderings("%lld days trained", 1).contains(d.summary), "\(d.summary)")
        #expect(CatalogPlural.english("%lld days trained", 1) == "1 day trained")
    }

    @Test func accessibilityLabelForRestAndTrained() {
        let cal = utcCalendar()
        let start = date("2026-01-01T00:00:00Z")
        let end = date("2026-01-03T00:00:00Z")
        let sessions = [date("2026-01-01T09:00:00Z")]
        let d = ConsistencyHeatmapPresenter.display(sessionDates: sessions,
                                                    range: DateInterval(start: start, end: end),
                                                    calendar: cal)
        #expect(d.cells[0].accessibilityLabel.contains("1 session"))
        #expect(d.cells[1].accessibilityLabel.contains("rest day"))
    }

    @Test func shadeCoversFullRamp() {
        #expect(ConsistencyHeatmapPresenter.Shade.allCases.count == 5)
        #expect(ConsistencyHeatmapPresenter.Shade(rawValue: 4) == .peak)
    }
}
