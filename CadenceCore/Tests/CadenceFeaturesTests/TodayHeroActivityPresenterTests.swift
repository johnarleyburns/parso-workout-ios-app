import XCTest
import SwiftData
import CadenceCore
@testable import CadenceFeatures

@MainActor
final class TodayHeroActivityPresenterTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let cal = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        container = try CadenceStore.makeModelContainer(inMemory: true)
        context = ModelContext(container)
    }

    private func session(title: String = "Push", end: Date?, deleted: Bool = false,
                         sets: [(String, Int, Bool, Bool)] = [("Bench", 5, false, true)]) -> WorkoutSession {
        let s = WorkoutSession(title: title, date: (end ?? now).addingTimeInterval(-3_600), endedAt: end)
        s.deletedAt = deleted ? now : nil
        context.insert(s)
        var ex: [String: Exercise] = [:]
        for (i, r) in sets.enumerated() {
            let e = ex[r.0] ?? Exercise(name: r.0)
            if ex[r.0] == nil { context.insert(e); ex[r.0] = e }
            context.insert(SetEntry(weight: 50, reps: r.1, order: i, session: s, exercise: e,
                                    performedBy: r.3 ? nil : Person(name: "Sam")))
        }
        return s
    }

    private func plan(_ title: String) -> EditablePlan {
        EditablePlan(title: title, warmupMinutes: 0, cooldownMinutes: 0, exercises: [EditableExercise(
            name: "Squat", sets: [EditableSet(targetReps: 5, targetWeight: 100)], notes: "")])
    }

    private func scheduled(_ date: Date, title: String, deleted: Bool = false) throws -> ScheduledWorkout {
        let plan = plan(title)
        let w = ScheduledWorkout(scheduledDate: date, title: title,
                                 payloadData: try ScheduledWorkoutStore.encode(plan),
                                 payloadVersion: ScheduledWorkoutStore.currentPayloadVersion)
        w.deletedAt = deleted ? now : nil
        context.insert(w)
        return w
    }

    func testEmptyIsNotLoadedAndLoadedEmptyIs() {
        XCTAssertFalse(TodayHeroActivitySnapshot.empty.isLoaded)
        let snap = TodayHeroActivityPresenter.make(sessions: [], scheduled: [], now: now, calendar: cal)
        XCTAssertTrue(snap.isLoaded)
        XCTAssertEqual(snap.completedWorkoutCount, 0)
    }

    func testCompletedTodayCountsDeletedAndBoundary() throws {
        let today = session(end: now)
        _ = session(title: "Gone", end: now, deleted: true)
        _ = session(title: "Yesterday", end: cal.startOfDay(for: now).addingTimeInterval(-1))
        _ = session(title: "Active", end: nil)
        let all = try context.fetch(FetchDescriptor<WorkoutSession>())
        let snap = TodayHeroActivityPresenter.make(sessions: all, scheduled: [], now: now, calendar: cal)
        XCTAssertEqual(snap.completedToday?.title, today.title)
        XCTAssertEqual(snap.completedToday?.setCount, 1)
        XCTAssertEqual(snap.completedToday?.exercises, [TodayHero.Line(name: "Bench", detail: "1 × 5")])
        // Deleted excluded; the rest (including the active session) have sets.
        XCTAssertEqual(snap.completedWorkoutCount, 3)
    }

    func testPartnerSetsExcludedFromOwnerSummary() throws {
        _ = session(end: now, sets: [("Bench", 5, false, true), ("Bench", 8, false, false)])
        let all = try context.fetch(FetchDescriptor<WorkoutSession>())
        let snap = TodayHeroActivityPresenter.make(sessions: all, scheduled: [], now: now, calendar: cal)
        XCTAssertEqual(snap.completedToday?.setCount, 1)
        XCTAssertEqual(snap.completedToday?.exercises.first?.detail, "1 × 5")
    }

    func testScheduledTodayNextAndDeleted() throws {
        let startOfToday = cal.startOfDay(for: now)
        _ = try scheduled(startOfToday.addingTimeInterval(7 * 3_600), title: "Today")
        _ = try scheduled(startOfToday.addingTimeInterval(2 * 86_400), title: "Later")
        _ = try scheduled(startOfToday.addingTimeInterval(86_400), title: "Tomorrow")
        _ = try scheduled(startOfToday.addingTimeInterval(8 * 3_600), title: "Deleted", deleted: true)
        let rows = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let snap = TodayHeroActivityPresenter.make(sessions: [], scheduled: rows, now: now, calendar: cal)
        XCTAssertEqual(snap.todayScheduled?.title, "Today")
        XCTAssertEqual(snap.todayScheduled?.exercises, [TodayHero.Line(name: "Squat", detail: "1 × 5")])
        XCTAssertNotNil(snap.todayScheduled?.durationMinutes)
        XCTAssertEqual(snap.remainingScheduledToday, 1)
        XCTAssertEqual(snap.nextScheduled?.title, "Tomorrow")
    }

    func testDurationSamplesMatchHistoryEstimate() throws {
        for i in 0..<3 { _ = session(title: "S\(i)", end: now.addingTimeInterval(Double(-i) * 86_400)) }
        let all = try context.fetch(FetchDescriptor<WorkoutSession>())
        let plan = plan("P")
        let snap = TodayHeroActivityPresenter.make(sessions: all, scheduled: [], now: now, calendar: cal)
        XCTAssertEqual(snap.suggestedDurationMinutes(plan: plan),
                       WorkoutDurationEstimator.estimate(plan: plan, history: all)?.minutes)
    }

    func testSnapshotDrivesHeroWithoutHistoryAndNeverFalseRecovery() {
        let snap = TodayHeroActivityPresenter.make(sessions: [], scheduled: [], now: now, calendar: cal)
        let hero = TodayHeroPresenter.hero(
            inProgress: nil, scheduled: snap.todayScheduled?.makeHero(), suggested: nil,
            completedWorkoutCount: snap.completedWorkoutCount, completedToday: snap.daySummary(),
            remainingScheduledToday: snap.remainingScheduledToday)
        // Day-one install: no starter plan yet means the hero is loading, never recovery.
        XCTAssertEqual(hero.kind, .loading)
    }
}
