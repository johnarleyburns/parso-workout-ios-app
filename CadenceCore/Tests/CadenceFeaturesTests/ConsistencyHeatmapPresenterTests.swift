import XCTest
@testable import CadenceFeatures
import CadenceCore

final class ConsistencyHeatmapPresenterTests: XCTestCase {

    private func utcCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func testDisplayMapsIntensityToShade() {
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
        XCTAssertEqual(d.cells.count, 2)
        XCTAssertEqual(d.cells[0].shade, .medium)   // 2 sessions
        XCTAssertEqual(d.cells[1].shade, .none)     // rest day
    }

    func testSummaryMentionsTrainedDaysAndStreak() {
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
        XCTAssertEqual(d.trainedDays, 2)
        XCTAssertEqual(d.currentStreak, 2)
        XCTAssertEqual(d.summary, "2 days trained \u{00b7} 2-day streak")
    }

    func testSummaryOmitsStreakBelowTwo() {
        let cal = utcCalendar()
        let start = date("2026-01-01T00:00:00Z")
        let end = date("2026-01-03T00:00:00Z")
        let sessions = [date("2026-01-01T09:00:00Z")]  // Jan 2 rest → no trailing streak
        let d = ConsistencyHeatmapPresenter.display(sessionDates: sessions,
                                                    range: DateInterval(start: start, end: end),
                                                    calendar: cal)
        XCTAssertEqual(d.summary, "1 day trained")
    }

    func testAccessibilityLabelForRestAndTrained() {
        let cal = utcCalendar()
        let start = date("2026-01-01T00:00:00Z")
        let end = date("2026-01-03T00:00:00Z")
        let sessions = [date("2026-01-01T09:00:00Z")]
        let d = ConsistencyHeatmapPresenter.display(sessionDates: sessions,
                                                    range: DateInterval(start: start, end: end),
                                                    calendar: cal)
        XCTAssertTrue(d.cells[0].accessibilityLabel.contains("1 session"))
        XCTAssertTrue(d.cells[1].accessibilityLabel.contains("rest day"))
    }

    func testShadeCoversFullRamp() {
        XCTAssertEqual(ConsistencyHeatmapPresenter.Shade.allCases.count, 5)
        XCTAssertEqual(ConsistencyHeatmapPresenter.Shade(rawValue: 4), .peak)
    }
}
