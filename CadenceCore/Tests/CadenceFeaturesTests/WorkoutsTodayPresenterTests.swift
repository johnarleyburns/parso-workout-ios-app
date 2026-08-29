import XCTest
import CadenceCore
@testable import CadenceFeatures

/// Field test 2026-08-18 #6: Workouts Today rows carry detail, a plan-source
/// badge and a startable prescription. Ordering, badge vocabulary and the
/// planned-volume arithmetic are asserted here, not in the simulator.
final class WorkoutsTodayPresenterTests: XCTestCase {

    private var now: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 18; c.hour = 12; c.minute = 0; c.second = 0
        return Calendar.current.date(from: c) ?? Date()
    }
    private var cal: Calendar { .current }

    private func strengthSession(_ title: String, endedMinutesAgo: Int) -> WorkoutSession {
        let s = WorkoutSession(title: title, date: now.addingTimeInterval(-Double(endedMinutesAgo) * 60))
        s.endedAt = now.addingTimeInterval(-Double(endedMinutesAgo) * 60 + 1800)
        return s
    }

    private func plan(_ id: String = "plan1",
                      kind: CoachSessionKind = .strength,
                      title: String = "Upper body — push emphasis",
                      subtitle: String = "Closes this week's chest deficit.",
                      durationMinutes: Int? = 45,
                      exercises: [CoachSession.RecommendedExercise]? = nil,
                      intensity: CoachSession.AerobicIntensity? = nil,
                      modality: CoachSession.AerobicModality? = nil,
                      citationIds: [String] = ["schoenfeldVolume2017"]) -> CoachSession {
        CoachSession(id: id, kind: kind, title: title, subtitle: subtitle,
                     durationMinutes: durationMinutes,
                     exercises: exercises ?? [
                        .init(name: "Bench Press", sets: 3, repsLow: 8, repsHigh: 12, loadKg: 45),
                        .init(name: "Overhead Press", sets: 3, repsLow: 8, repsHigh: 12, loadKg: 30)
                     ],
                     modality: modality, intensity: intensity,
                     citationIds: citationIds,
                     launchPayload: kind == .strength ? .strengthPlan("push")
                                                      : .cardio(type: "run", durationMinutes: durationMinutes))
    }

    // MARK: - Ordering

    func testCompletedRowsComeFirstNewestFirst() {
        let older = strengthSession("Morning", endedMinutesAgo: 300)
        let newer = strengthSession("Lunch", endedMinutesAgo: 60)
        let rows = WorkoutsTodayPresenter.rows(sessions: [older, newer], cardio: [],
                                               plannedToday: [plan()], now: now, calendar: cal)
        XCTAssertEqual(rows.map(\.title), ["Lunch", "Morning", "Upper body — push emphasis"])
        XCTAssertEqual(rows.prefix(2).map(\.status), [.completed, .completed])
    }

    func testPlannedRowsFollowInPlanOrder() {
        let a = plan("a", title: "First")
        let b = plan("b", title: "Second")
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [],
                                               plannedToday: [a, b], now: now, calendar: cal)
        XCTAssertEqual(rows.map(\.title), ["First", "Second"])
    }

    // MARK: - Badges

    func testPlannedBadgeSaysCoachsPlanForCoachSource() {
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [plan()],
                                               source: .coach, now: now, calendar: cal)
        XCTAssertEqual(rows.first?.status.badgeText, "COACH'S PLAN")
    }

    func testPlannedBadgeSaysYourPlanForUserSource() {
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [plan()],
                                               source: .user, now: now, calendar: cal)
        XCTAssertEqual(rows.first?.status.badgeText, "YOUR PLAN")
    }

    func testPlannedBadgeSaysTrainersPlanForTrainerSource() {
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [plan()],
                                               source: .trainer, now: now, calendar: cal)
        XCTAssertEqual(rows.first?.status.badgeText, "TRAINER'S PLAN")
    }

    func testCompletedBadgeSaysCompleted() {
        let rows = WorkoutsTodayPresenter.rows(sessions: [strengthSession("Push", endedMinutesAgo: 30)],
                                               cardio: [], plannedToday: [], now: now, calendar: cal)
        XCTAssertEqual(rows.first?.status.badgeText, "COMPLETED")
    }

    // MARK: - Filtering

    func testNoRowsWhenNothingCompletedOrPlanned() {
        XCTAssertTrue(WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [],
                                                  now: now, calendar: cal).isEmpty)
    }

    func testDeletedSessionsAreExcluded() {
        let deleted = strengthSession("Deleted", endedMinutesAgo: 30)
        deleted.deletedAt = now
        let rows = WorkoutsTodayPresenter.rows(sessions: [deleted], cardio: [], plannedToday: [],
                                               now: now, calendar: cal)
        XCTAssertTrue(rows.isEmpty)
    }

    func testInProgressSessionIsNotCompleted() {
        let open = WorkoutSession(title: "Open", date: now.addingTimeInterval(-1800))
        XCTAssertTrue(open.isResumable, "precondition: a session with no endedAt is resumable")
        let rows = WorkoutsTodayPresenter.rows(sessions: [open], cardio: [], plannedToday: [],
                                               now: now, calendar: cal)
        XCTAssertTrue(rows.isEmpty)
    }

    func testPartialTwoADayKeepsTheOutstandingPlanVisible() {
        // Strength done this morning, the coach's cardio half still outstanding.
        let done = strengthSession("Push Day", endedMinutesAgo: 240)
        let outstanding = plan("cardio1", kind: .easyAerobic, title: "Easy run",
                               durationMinutes: 30, exercises: [],
                               intensity: .easy, modality: .run)
        let rows = WorkoutsTodayPresenter.rows(sessions: [done], cardio: [],
                                               plannedToday: [outstanding], now: now, calendar: cal)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.last?.title, "Easy run")
        XCTAssertEqual(rows.last?.status, .planned(.coach))
    }

    func testRestDaysAreNeverRows() {
        let rest = plan("rest1", kind: .rest, title: "Rest", exercises: [])
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [rest],
                                               now: now, calendar: cal)
        XCTAssertTrue(rows.isEmpty)
    }

    // MARK: - Row content

    func testStrengthSubtitleListsExerciseNames() {
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [plan()],
                                               now: now, calendar: cal)
        XCTAssertEqual(rows.first?.subtitle, "Bench Press, Overhead Press")
    }

    func testCardioRowCarriesDistanceAndDuration() {
        let run = CardioWorkout(type: .run, start: now.addingTimeInterval(-3600),
                                end: now.addingTimeInterval(-1800))
        run.distance = 5200
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [run], plannedToday: [],
                                               now: now, calendar: cal)
        XCTAssertEqual(rows.first?.modality, .cardio)
        XCTAssertEqual(rows.first?.value, "5.2 km · 30m")
    }

    func testPlannedExerciseRowsCarrySetsRepsAndLoad() {
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [plan()],
                                               now: now, calendar: cal)
        let bench = rows.first?.exercises.first
        XCTAssertEqual(bench?.name, "Bench Press")
        XCTAssertEqual(bench?.sets, 3)
        XCTAssertEqual(bench?.repsText, "8–12")
        XCTAssertEqual(bench?.loadKg, 45)
    }

    func testPlannedRepsTextUsesTheLadderWhenPresent() {
        let ladder = plan(exercises: [
            .init(name: "Bench Press", sets: 3, repsLow: 8, repsHigh: 12, loadKg: 45,
                  repLadder: [12, 10, 8])
        ])
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [ladder],
                                               now: now, calendar: cal)
        XCTAssertEqual(rows.first?.exercises.first?.repsText, "12, 10, 8")
    }

    func testPlannedRepsTextFallsBackToTheRepRange() {
        let single = plan(exercises: [.init(name: "Bench Press", sets: 3, repsLow: 10, loadKg: 45)])
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [single],
                                               now: now, calendar: cal)
        XCTAssertEqual(rows.first?.exercises.first?.repsText, "10")
    }

    // MARK: - Planned volume

    func testPlannedVolumeSumsSetsRepsTimesLoad() {
        // 3 × 8 × 45 = 1080, 3 × 8 × 30 = 720 → 1800 (priced at the bottom of
        // the rep range so the coach never over-promises tonnage).
        XCTAssertEqual(WorkoutsTodayPresenter.plannedVolumeKg(plan()) ?? 0, 1800, accuracy: 0.001)
    }

    func testPlannedVolumeUsesTheLadderWhenPresent() {
        let ladder = plan(exercises: [
            .init(name: "Bench Press", sets: 3, repsLow: 8, repsHigh: 12, loadKg: 45,
                  repLadder: [12, 10, 8])
        ])
        XCTAssertEqual(WorkoutsTodayPresenter.plannedVolumeKg(ladder) ?? 0, 30 * 45, accuracy: 0.001)
    }

    func testPlannedVolumeIsNilForAPureBodyweightPlan() {
        let bodyweight = plan(exercises: [
            .init(name: "Push-Up", sets: 3, repsLow: 12),
            .init(name: "Pull-Up", sets: 3, repsLow: 8)
        ])
        XCTAssertNil(WorkoutsTodayPresenter.plannedVolumeKg(bodyweight))
    }

    func testBodyweightExerciseIsFlaggedNotZeroLoaded() {
        let bodyweight = plan(exercises: [
            .init(name: "Push-Up", sets: 3, repsLow: 12),
            .init(name: "Barbell Row", sets: 3, repsLow: 10)
        ])
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [bodyweight],
                                               now: now, calendar: cal)
        let exercises = rows.first?.exercises ?? []
        XCTAssertEqual(exercises.first?.isBodyweight, true)
        XCTAssertNil(exercises.first?.loadKg)
        XCTAssertEqual(exercises.last?.isBodyweight, false,
                       "A loaded lift with no resolvable history is not bodyweight (field test #2)")
    }

    // MARK: - Value text

    func testPlannedValueTextForStrengthAndForCardio() {
        XCTAssertEqual(WorkoutsTodayPresenter.plannedValueText(plan()), "6 sets · ~45m")
        let run = plan("c", kind: .easyAerobic, title: "Easy run", durationMinutes: 30,
                       exercises: [], intensity: .easy, modality: .run)
        XCTAssertEqual(WorkoutsTodayPresenter.plannedValueText(run), "~30m easy")
    }

    // MARK: - Interaction affordances

    func testCompletedRowsAreNavigableAndPlannedRowsAreExpandable() {
        let rows = WorkoutsTodayPresenter.rows(sessions: [strengthSession("Push", endedMinutesAgo: 30)],
                                               cardio: [], plannedToday: [plan()],
                                               now: now, calendar: cal)
        let completed = rows.first { $0.status == .completed }
        let planned = rows.first { $0.status == .planned(.coach) }
        XCTAssertEqual(completed?.isNavigable, true)
        XCTAssertEqual(completed?.isExpandable, false)
        XCTAssertEqual(planned?.isExpandable, true)
        XCTAssertEqual(planned?.isNavigable, false)
    }

    func testShowMoreHistoryOnlyAppearsForCompletedRows() {
        let completed = WorkoutsTodayPresenter.rows(
            sessions: [strengthSession("Push", endedMinutesAgo: 30)],
            cardio: [], plannedToday: [], now: now, calendar: cal)
        let planned = WorkoutsTodayPresenter.rows(
            sessions: [], cardio: [], plannedToday: [plan()], now: now, calendar: cal)

        XCTAssertTrue(WorkoutsTodayPresenter.showsMoreHistory(for: completed))
        XCTAssertFalse(WorkoutsTodayPresenter.showsMoreHistory(for: planned))
        XCTAssertFalse(WorkoutsTodayPresenter.showsMoreHistory(for: []))
    }

    func testPlannedRowCarriesTheSessionCitationIds() {
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [plan()],
                                               now: now, calendar: cal)
        XCTAssertEqual(rows.first?.citationIds, ["schoenfeldVolume2017"])
        XCTAssertEqual(rows.first?.sourceKey, "plan1")
    }
}
