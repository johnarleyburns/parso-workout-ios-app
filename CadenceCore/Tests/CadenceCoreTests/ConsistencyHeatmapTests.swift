import XCTest
@testable import CadenceCore

final class ConsistencyHeatmapTests: XCTestCase {

    private func utcCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ iso: String, calendar: Calendar) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = calendar.timeZone
        return f.date(from: iso)!
    }

    // MARK: - Day bucketing

    func testDayBucketingCountsSessionsPerDay() {
        let cal = utcCalendar()
        let start = date("2026-01-01T00:00:00Z", calendar: cal)
        let end = date("2026-01-04T00:00:00Z", calendar: cal)
        let sessions = [
            date("2026-01-01T09:00:00Z", calendar: cal),
            date("2026-01-01T18:00:00Z", calendar: cal),  // same day → count 2
            date("2026-01-03T07:00:00Z", calendar: cal)
        ]
        let days = ConsistencyHeatmap.days(sessionDates: sessions,
                                           range: DateInterval(start: start, end: end),
                                           calendar: cal)
        XCTAssertEqual(days.count, 3)             // Jan 1, 2, 3 (half-open, excludes Jan 4)
        XCTAssertEqual(days[0].sessionCount, 2)   // Jan 1
        XCTAssertEqual(days[1].sessionCount, 0)   // Jan 2 rest
        XCTAssertEqual(days[2].sessionCount, 1)   // Jan 3
    }

    // MARK: - Multiple sessions in one day

    func testMultipleSessionsInOneDay() {
        let cal = utcCalendar()
        let start = date("2026-01-01T00:00:00Z", calendar: cal)
        let end = date("2026-01-02T00:00:00Z", calendar: cal)
        let sessions = [
            date("2026-01-01T06:00:00Z", calendar: cal),
            date("2026-01-01T12:00:00Z", calendar: cal),
            date("2026-01-01T18:00:00Z", calendar: cal)
        ]
        let days = ConsistencyHeatmap.days(sessionDates: sessions,
                                           range: DateInterval(start: start, end: end),
                                           calendar: cal)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].sessionCount, 3)
        XCTAssertEqual(days[0].intensity, 3)
    }

    // MARK: - Intensity ramp saturates at 4

    func testIntensityRampSaturatesAtFour() {
        XCTAssertEqual(ConsistencyHeatmap.intensity(forSessionCount: 0), 0)
        XCTAssertEqual(ConsistencyHeatmap.intensity(forSessionCount: 1), 1)
        XCTAssertEqual(ConsistencyHeatmap.intensity(forSessionCount: 4), 4)
        XCTAssertEqual(ConsistencyHeatmap.intensity(forSessionCount: 9), 4)  // saturates
    }

    // MARK: - Empty range

    func testEmptyRangeProducesNoDays() {
        let cal = utcCalendar()
        let d = date("2026-01-01T00:00:00Z", calendar: cal)
        let days = ConsistencyHeatmap.days(sessionDates: [],
                                           range: DateInterval(start: d, end: d),
                                           calendar: cal)
        XCTAssertTrue(days.isEmpty)
    }

    func testRangeWithNoSessionsAllRestDays() {
        let cal = utcCalendar()
        let start = date("2026-01-01T00:00:00Z", calendar: cal)
        let end = date("2026-01-08T00:00:00Z", calendar: cal)
        let days = ConsistencyHeatmap.days(sessionDates: [],
                                           range: DateInterval(start: start, end: end),
                                           calendar: cal)
        XCTAssertEqual(days.count, 7)
        XCTAssertTrue(days.allSatisfy { $0.sessionCount == 0 && $0.intensity == 0 })
    }

    // MARK: - DST transition (the classic off-by-one-day bug)

    func testDSTSpringForwardAdvancesByCalendarDay() {
        // US spring-forward 2026: 2 AM → 3 AM on Mar 8. A day is only 23h long.
        // Walking by a fixed 86 400 s would skip/duplicate a day; the calendar walk
        // must produce exactly one cell per calendar day.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let start = date("2026-03-07T00:00:00-05:00", calendar: cal)
        let end = date("2026-03-10T00:00:00-04:00", calendar: cal)  // note offset shift
        let days = ConsistencyHeatmap.days(sessionDates: [],
                                           range: DateInterval(start: start, end: end),
                                           calendar: cal)
        XCTAssertEqual(days.count, 3)   // Mar 7, 8, 9 — the DST day is not lost/dup'd
        let comps = days.map { cal.component(.day, from: $0.date) }
        XCTAssertEqual(comps, [7, 8, 9])
    }

    func testDSTFallBackAdvancesByCalendarDay() {
        // US fall-back 2026: Nov 1 is 25h long.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let start = date("2026-10-31T00:00:00-04:00", calendar: cal)
        let end = date("2026-11-03T00:00:00-05:00", calendar: cal)
        let days = ConsistencyHeatmap.days(sessionDates: [],
                                           range: DateInterval(start: start, end: end),
                                           calendar: cal)
        XCTAssertEqual(days.count, 3)
        let comps = days.map { cal.component(.day, from: $0.date) }
        XCTAssertEqual(comps, [31, 1, 2])
    }

    // MARK: - Timezone changes

    func testTimezoneAffectsDayBucket() {
        // A session at 23:00 UTC lands on different calendar days in UTC vs UTC-5.
        let utc = utcCalendar()
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!

        let session = ISO8601DateFormatter().date(from: "2026-01-02T03:00:00Z")! // 22:00 EST prev day

        let utcRange = DateInterval(start: date("2026-01-01T00:00:00Z", calendar: utc),
                                    end: date("2026-01-04T00:00:00Z", calendar: utc))
        let utcDays = ConsistencyHeatmap.days(sessionDates: [session], range: utcRange, calendar: utc)
        // In UTC the session is on Jan 2.
        XCTAssertEqual(utcDays.first { $0.sessionCount > 0 }.map { utc.component(.day, from: $0.date) }, 2)

        let easternStart = eastern.startOfDay(for: ISO8601DateFormatter().date(from: "2026-01-01T12:00:00Z")!)
        let easternEnd = eastern.date(byAdding: .day, value: 3, to: easternStart)!
        let easternDays = ConsistencyHeatmap.days(sessionDates: [session],
                                                  range: DateInterval(start: easternStart, end: easternEnd),
                                                  calendar: eastern)
        // In Eastern the same instant is 22:00 on Jan 1.
        XCTAssertEqual(easternDays.first { $0.sessionCount > 0 }.map { eastern.component(.day, from: $0.date) }, 1)
    }

    // MARK: - Streaks

    func testCurrentStreakCountsTrailingTrainedDays() {
        let cal = utcCalendar()
        let start = date("2026-01-01T00:00:00Z", calendar: cal)
        let end = date("2026-01-06T00:00:00Z", calendar: cal)  // 5 days
        let sessions = [
            date("2026-01-01T09:00:00Z", calendar: cal),  // trained
            // Jan 2 rest
            date("2026-01-04T09:00:00Z", calendar: cal),  // trained
            date("2026-01-05T09:00:00Z", calendar: cal)   // trained (trailing)
        ]
        let days = ConsistencyHeatmap.days(sessionDates: sessions,
                                           range: DateInterval(start: start, end: end),
                                           calendar: cal)
        XCTAssertEqual(ConsistencyHeatmap.currentStreak(days: days), 2)  // Jan 4,5
        XCTAssertEqual(ConsistencyHeatmap.longestStreak(days: days), 2)
    }

    func testCurrentStreakZeroWhenLastDayIsRest() {
        let cal = utcCalendar()
        let start = date("2026-01-01T00:00:00Z", calendar: cal)
        let end = date("2026-01-04T00:00:00Z", calendar: cal)
        let sessions = [date("2026-01-01T09:00:00Z", calendar: cal)]  // Jan 3 is rest
        let days = ConsistencyHeatmap.days(sessionDates: sessions,
                                           range: DateInterval(start: start, end: end),
                                           calendar: cal)
        XCTAssertEqual(ConsistencyHeatmap.currentStreak(days: days), 0)
    }
}
