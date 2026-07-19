import XCTest
import CadenceCore
@testable import CadenceFeatures

/// Phase D (field-test-fixes): true today-list presenter for "What you did."
final class TodayActivityPresenterTests: XCTestCase {

    private var now: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 18; c.hour = 12; c.minute = 0; c.second = 0
        return Calendar.current.date(from: c) ?? Date()
    }

    private var cal: Calendar { .current }

    // MARK: - includesOnlyToday

    func testIncludesOnlyToday() {
        let today1 = WorkoutSession(title: "Today AM", date: now.addingTimeInterval(-3600))
        today1.endedAt = now.addingTimeInterval(-3000)
        let yesterday = WorkoutSession(title: "Yesterday", date: now.addingTimeInterval(-86400))
        yesterday.endedAt = now.addingTimeInterval(-82800)
        let tomorrow = WorkoutSession(title: "Tomorrow", date: now.addingTimeInterval(86400))
        tomorrow.endedAt = now.addingTimeInterval(90000)

        let entries = TodayActivityPresenter.entries(
            sessions: [today1, yesterday, tomorrow], cardio: [], now: now, calendar: cal)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.title, "Today AM")
    }

    // MARK: - inProgressExcluded

    func testInProgressExcluded() {
        let inProgress = WorkoutSession(title: "Open", date: now.addingTimeInterval(-1800))
        // endedAt nil → isResumable → excluded
        let completed = WorkoutSession(title: "Done", date: now.addingTimeInterval(-900))
        completed.endedAt = now.addingTimeInterval(-600)

        let entries = TodayActivityPresenter.entries(
            sessions: [inProgress, completed], cardio: [], now: now, calendar: cal)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.title, "Done")
    }

    // MARK: - deletedExcluded

    func testDeletedExcluded() {
        let deleted = WorkoutSession(title: "Deleted", date: now.addingTimeInterval(-1800))
        deleted.endedAt = now.addingTimeInterval(-1500)
        deleted.deletedAt = now
        let kept = WorkoutSession(title: "Kept", date: now.addingTimeInterval(-3600))
        kept.endedAt = now.addingTimeInterval(-3000)

        let entries = TodayActivityPresenter.entries(
            sessions: [deleted, kept], cardio: [], now: now, calendar: cal)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.title, "Kept")
    }

    // MARK: - multipleSameDayAllListed

    func testMultipleSameDayAllListed() {
        let s1 = WorkoutSession(title: "Morning", date: now.addingTimeInterval(-7200))
        s1.endedAt = now.addingTimeInterval(-6600)
        let s2 = WorkoutSession(title: "Afternoon", date: now.addingTimeInterval(-3600))
        s2.endedAt = now.addingTimeInterval(-3000)

        let entries = TodayActivityPresenter.entries(
            sessions: [s1, s2], cardio: [], now: now, calendar: cal)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.map(\.title).contains("Morning"))
        XCTAssertTrue(entries.map(\.title).contains("Afternoon"))
    }

    // MARK: - mixedSortedNewestFirst

    func testMixedSortedNewestFirst() {
        let earlier = WorkoutSession(title: "Earlier", date: now.addingTimeInterval(-7200))
        earlier.endedAt = now.addingTimeInterval(-6600)
        let later = WorkoutSession(title: "Later", date: now.addingTimeInterval(-1800))
        later.endedAt = now.addingTimeInterval(-1200)

        let entries = TodayActivityPresenter.entries(
            sessions: [earlier, later], cardio: [], now: now, calendar: cal)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].title, "Later")
        XCTAssertEqual(entries[1].title, "Earlier")
    }

    // MARK: - midnightBoundary

    func testMidnightBoundary() {
        let todayStart = cal.startOfDay(for: now)
        let justAfterMidnight = WorkoutSession(title: "Late Night", date: todayStart.addingTimeInterval(60))
        justAfterMidnight.endedAt = todayStart.addingTimeInterval(3600)
        let beforeMidnight = WorkoutSession(title: "Last Night", date: todayStart.addingTimeInterval(-60))
        beforeMidnight.endedAt = todayStart.addingTimeInterval(-30)

        let entries = TodayActivityPresenter.entries(
            sessions: [justAfterMidnight, beforeMidnight], cardio: [], now: now, calendar: cal)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.title, "Late Night")
    }

    // MARK: - unitFormatting

    func testUnitFormatting() {
        let s = WorkoutSession(title: "Squat day", date: now.addingTimeInterval(-3600))
        s.endedAt = now.addingTimeInterval(-1200)
        let entries = TodayActivityPresenter.entries(sessions: [s], cardio: [], now: now, calendar: cal)
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].value.contains("m"), "Should format duration")
    }

    // MARK: - emptyDay

    func testEmptyDay() {
        let entries = TodayActivityPresenter.entries(sessions: [], cardio: [], now: now, calendar: cal)
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - observedFacts defect: engine observedFacts yields ≤1 strength

    /// Documents the old source's defect: `coachDecision.observedFacts`
    /// yields ≤1 strength entry, which means a user with two completed-today
    /// sessions would only see one in "What you did".
    func testMultipleStrengthTodayAllVisible() {
        let s1 = WorkoutSession(title: "Push", date: now.addingTimeInterval(-10800))
        s1.endedAt = now.addingTimeInterval(-7200)
        let s2 = WorkoutSession(title: "Pull", date: now.addingTimeInterval(-3600))
        s2.endedAt = now.addingTimeInterval(-1800)

        let entries = TodayActivityPresenter.entries(
            sessions: [s1, s2], cardio: [], now: now, calendar: cal)
        XCTAssertEqual(entries.count, 2,
                       "Two completed-today sessions must both appear (old observedFacts showed ≤1)")
    }

    // MARK: - resumable excluded (joint invariant)

    func testResumableExcluded() {
        let resumable = WorkoutSession(title: "In Progress", date: now.addingTimeInterval(-1800))
        // endedAt nil → isResumable means excluded by presenter
        let completed = WorkoutSession(title: "Completed", date: now.addingTimeInterval(-3600))
        completed.endedAt = now.addingTimeInterval(-3000)

        let entries = TodayActivityPresenter.entries(
            sessions: [resumable, completed], cardio: [], now: now, calendar: cal)
        XCTAssertEqual(entries.count, 1)
        // The resumable session is excluded because the Resume card covers it.
    }
}
