import Foundation
import Testing
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

/// Field test 2026-08-18 #6: Workouts Today rows carry detail, a plan-source
/// badge and a startable prescription. Ordering, badge vocabulary and the
/// planned-volume arithmetic are asserted here, not in the simulator.
struct WorkoutsTodayPresenterTests {

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

    @Test func completedRowsComeFirstNewestFirst() {
        let older = strengthSession("Morning", endedMinutesAgo: 300)
        let newer = strengthSession("Lunch", endedMinutesAgo: 60)
        let rows = WorkoutsTodayPresenter.rows(sessions: [older, newer], cardio: [],
                                               plannedToday: [plan()], now: now, calendar: cal)
        #expect(rows.map(\.title) == ["Lunch", "Morning", "Upper body — push emphasis"])
        #expect(rows.prefix(2).map(\.status) == [.completed, .completed])
    }

    @Test func historicalRowsOnlyShowsWorkoutsActuallyCompleted() {
        let completed = strengthSession("Lifted today", endedMinutesAgo: 30)
        let rows = WorkoutsTodayPresenter.historicalRows(
            sessions: [completed], cardio: [], now: now, calendar: cal)

        #expect(rows.map(\.title) == ["Lifted today"])
        #expect(rows.allSatisfy { $0.status == .completed })
        #expect(!rows.contains { $0.title.localizedCaseInsensitiveContains("plan") })
    }

    @Test func historicalRowsIsEmptyWithoutCompletedHistory() {
        #expect(WorkoutsTodayPresenter.historicalRows(
            sessions: [], cardio: [], now: now, calendar: cal).isEmpty)
    }

    @Test func plannedRowsFollowInPlanOrder() {
        let a = plan("a", title: "First")
        let b = plan("b", title: "Second")
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [],
                                               plannedToday: [a, b], now: now, calendar: cal)
        #expect(rows.map(\.title) == ["First", "Second"])
    }

    // MARK: - Badges

    @Test func plannedBadgeSaysCoachsPlanForCoachSource() {
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [plan()],
                                               source: .coach, now: now, calendar: cal)
        #expect(rows.first?.status.badgeText == "COACH'S PLAN")
    }

    @Test func plannedBadgeSaysYourPlanForUserSource() {
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [plan()],
                                               source: .user, now: now, calendar: cal)
        #expect(rows.first?.status.badgeText == "YOUR PLAN")
    }

    @Test func plannedBadgeSaysTrainersPlanForTrainerSource() {
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [plan()],
                                               source: .trainer, now: now, calendar: cal)
        #expect(rows.first?.status.badgeText == "TRAINER'S PLAN")
    }

    @Test func completedBadgeSaysCompleted() {
        let rows = WorkoutsTodayPresenter.rows(sessions: [strengthSession("Push", endedMinutesAgo: 30)],
                                               cardio: [], plannedToday: [], now: now, calendar: cal)
        #expect(rows.first?.status.badgeText == "COMPLETED")
    }

    // MARK: - Filtering

    @Test func noRowsWhenNothingCompletedOrPlanned() {
        #expect(WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [],
                                                  now: now, calendar: cal).isEmpty)
    }

    @Test func deletedSessionsAreExcluded() {
        let deleted = strengthSession("Deleted", endedMinutesAgo: 30)
        deleted.deletedAt = now
        let rows = WorkoutsTodayPresenter.rows(sessions: [deleted], cardio: [], plannedToday: [],
                                               now: now, calendar: cal)
        #expect(rows.isEmpty)
    }

    @Test func inProgressSessionIsNotCompleted() {
        let open = WorkoutSession(title: "Open", date: now.addingTimeInterval(-1800))
        #expect(open.isResumable, "precondition: a session with no endedAt is resumable")
        let rows = WorkoutsTodayPresenter.rows(sessions: [open], cardio: [], plannedToday: [],
                                               now: now, calendar: cal)
        #expect(rows.isEmpty)
    }

    @Test func partialTwoADayKeepsTheOutstandingPlanVisible() {
        // Strength done this morning, the coach's cardio half still outstanding.
        let done = strengthSession("Push Day", endedMinutesAgo: 240)
        let outstanding = plan("cardio1", kind: .easyAerobic, title: "Easy run",
                               durationMinutes: 30, exercises: [],
                               intensity: .easy, modality: .run)
        let rows = WorkoutsTodayPresenter.rows(sessions: [done], cardio: [],
                                               plannedToday: [outstanding], now: now, calendar: cal)
        #expect(rows.count == 2)
        #expect(rows.last?.title == "Easy run")
        #expect(rows.last?.status == .planned(.coach))
    }

    @Test func restDaysAreNeverRows() {
        let rest = plan("rest1", kind: .rest, title: "Rest", exercises: [])
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [rest],
                                               now: now, calendar: cal)
        #expect(rows.isEmpty)
    }

    // MARK: - Row content

    @Test func strengthSubtitleListsExerciseNames() {
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [plan()],
                                               now: now, calendar: cal)
        #expect(rows.first?.subtitle == "Bench Press, Overhead Press")
    }

    @Test func cardioRowCarriesDistanceAndDuration() {
        let run = CardioWorkout(type: .run, start: now.addingTimeInterval(-3600),
                                end: now.addingTimeInterval(-1800))
        run.distance = 5200
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [run], plannedToday: [],
                                               now: now, calendar: cal)
        #expect(rows.first?.modality == .cardio)
        #expect(rows.first?.value == "5.2 km · 30m")
    }

    @Test func completedTodayRowsResolveStableStrengthAndCardioHistoryRoutes() {
        let session = strengthSession("Push", endedMinutesAgo: 30)
        let run = CardioWorkout(type: .run, start: now.addingTimeInterval(-3600),
                                end: now.addingTimeInterval(-1800))
        let rows = WorkoutsTodayPresenter.historicalRows(
            sessions: [session], cardio: [run], now: now, calendar: cal)

        #expect(rows.allSatisfy { WorkoutsTodayPresenter.historyRoute(for: $0) != nil })
        #expect(rows.contains {
            WorkoutsTodayPresenter.historyRoute(for: $0) == .strength(session.id)
        })
        #expect(rows.contains {
            WorkoutsTodayPresenter.historyRoute(for: $0) == .cardio(run.id)
        })
    }

    @Test func plannedRowsNeverProduceAHistoryRoute() throws {
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [plan()],
                                               now: now, calendar: cal)
        #expect(WorkoutsTodayPresenter.historyRoute(for: try #require(rows.first)) == nil)
    }

    @Test func plannedExerciseRowsCarrySetsRepsAndLoad() {
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [plan()],
                                               now: now, calendar: cal)
        let bench = rows.first?.exercises.first
        #expect(bench?.name == "Bench Press")
        #expect(bench?.sets == 3)
        #expect(bench?.repsText == "8–12")
        #expect(bench?.loadKg == 45)
    }

    @Test func plannedRepsTextUsesTheLadderWhenPresent() {
        let ladder = plan(exercises: [
            .init(name: "Bench Press", sets: 3, repsLow: 8, repsHigh: 12, loadKg: 45,
                  repLadder: [12, 10, 8])
        ])
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [ladder],
                                               now: now, calendar: cal)
        #expect(rows.first?.exercises.first?.repsText == "12, 10, 8")
    }

    @Test func plannedRepsTextFallsBackToTheRepRange() {
        let single = plan(exercises: [.init(name: "Bench Press", sets: 3, repsLow: 10, loadKg: 45)])
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [single],
                                               now: now, calendar: cal)
        #expect(rows.first?.exercises.first?.repsText == "10")
    }

    // MARK: - Planned volume

    @Test func plannedVolumeSumsSetsRepsTimesLoad() {
        // 3 × 8 × 45 = 1080, 3 × 8 × 30 = 720 → 1800 (priced at the bottom of
        // the rep range so the coach never over-promises tonnage).
        #expect(abs((WorkoutsTodayPresenter.plannedVolumeKg(plan()) ?? 0) - 1800) <= 0.001)
    }

    @Test func plannedVolumeUsesTheLadderWhenPresent() {
        let ladder = plan(exercises: [
            .init(name: "Bench Press", sets: 3, repsLow: 8, repsHigh: 12, loadKg: 45,
                  repLadder: [12, 10, 8])
        ])
        #expect(abs((WorkoutsTodayPresenter.plannedVolumeKg(ladder) ?? 0) - 30 * 45) <= 0.001)
    }

    @Test func plannedVolumeIsNilForAPureBodyweightPlan() {
        let bodyweight = plan(exercises: [
            .init(name: "Push-Up", sets: 3, repsLow: 12),
            .init(name: "Pull-Up", sets: 3, repsLow: 8)
        ])
        #expect(WorkoutsTodayPresenter.plannedVolumeKg(bodyweight) == nil)
    }

    @Test func bodyweightExerciseIsFlaggedNotZeroLoaded() {
        let bodyweight = plan(exercises: [
            .init(name: "Push-Up", sets: 3, repsLow: 12),
            .init(name: "Barbell Row", sets: 3, repsLow: 10)
        ])
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [bodyweight],
                                               now: now, calendar: cal)
        let exercises = rows.first?.exercises ?? []
        #expect(exercises.first?.isBodyweight == true)
        #expect(exercises.first?.loadKg == nil)
        #expect(exercises.last?.isBodyweight == false,
                       "A loaded lift with no resolvable history is not bodyweight (field test #2)")
    }

    // MARK: - Value text

    @Test func plannedValueTextForStrengthAndForCardio() {
        #expect(WorkoutsTodayPresenter.plannedValueText(plan()) == "6 sets · ~45m")
        let run = plan("c", kind: .easyAerobic, title: "Easy run", durationMinutes: 30,
                       exercises: [], intensity: .easy, modality: .run)
        #expect(WorkoutsTodayPresenter.plannedValueText(run) == "~30m easy")
    }

    // MARK: - Interaction affordances

    @Test func completedRowsAreNavigableAndPlannedRowsAreExpandable() {
        let rows = WorkoutsTodayPresenter.rows(sessions: [strengthSession("Push", endedMinutesAgo: 30)],
                                               cardio: [], plannedToday: [plan()],
                                               now: now, calendar: cal)
        let completed = rows.first { $0.status == .completed }
        let planned = rows.first { $0.status == .planned(.coach) }
        #expect(completed?.isNavigable == true)
        #expect(completed?.isExpandable == false)
        #expect(planned?.isExpandable == true)
        #expect(planned?.isNavigable == false)
    }

    @Test func showMoreHistoryOnlyAppearsForCompletedRows() {
        let completed = WorkoutsTodayPresenter.rows(
            sessions: [strengthSession("Push", endedMinutesAgo: 30)],
            cardio: [], plannedToday: [], now: now, calendar: cal)
        let planned = WorkoutsTodayPresenter.rows(
            sessions: [], cardio: [], plannedToday: [plan()], now: now, calendar: cal)

        #expect(WorkoutsTodayPresenter.showsMoreHistory(for: completed))
        #expect(!WorkoutsTodayPresenter.showsMoreHistory(for: planned))
        #expect(!WorkoutsTodayPresenter.showsMoreHistory(for: []))
    }

    @Test func plannedRowCarriesTheSessionCitationIds() {
        let rows = WorkoutsTodayPresenter.rows(sessions: [], cardio: [], plannedToday: [plan()],
                                               now: now, calendar: cal)
        #expect(rows.first?.citationIds == ["schoenfeldVolume2017"])
        #expect(rows.first?.sourceKey == "plan1")
    }
}
