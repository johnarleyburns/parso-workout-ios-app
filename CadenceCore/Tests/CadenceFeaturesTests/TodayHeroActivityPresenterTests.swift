#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

@MainActor
final class TodayHeroActivityPresenterTests {

    @Test func cardioCompletionDoesNotCreateAStrengthDoneSummary() {
        let cardio = TodayHeroActivitySnapshot.CompletedWorkout(
            title: "Easy Cycle", modality: .cardio, setCount: 0, volumeKg: 0,
            durationMinutes: 30, exercises: [], occurredAt: Date())
        let snapshot = TodayHeroActivitySnapshot(
            completedWorkoutCount: 3, completedToday: [cardio], nextScheduled: nil,
            todayScheduled: nil, remainingScheduledToday: 0, durationSamples: [])

        #expect(snapshot.strengthDaySummary() == nil)
        #expect(snapshot.latestCompletedCardio?.title == "Easy Cycle")

        let strengthSuggestion = TodayHero(kind: .suggested, title: "Upper Body")
        let hero = TodayHeroPresenter.hero(
            inProgress: nil, scheduled: nil, suggested: strengthSuggestion,
            completedWorkoutCount: snapshot.completedWorkoutCount,
            completedToday: snapshot.strengthDaySummary())
        #expect(hero.kind == .suggested)
        #expect(hero.title == "Upper Body")
    }
    private var container: ModelContainer!
    private var context: ModelContext!
    private let cal = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() async throws {
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

    @Test func emptyIsNotLoadedAndLoadedEmptyIs() {
        #expect(!TodayHeroActivitySnapshot.empty.isLoaded)
        let snap = TodayHeroActivityPresenter.make(sessions: [], scheduled: [], now: now, calendar: cal)
        #expect(snap.isLoaded)
        #expect(snap.completedWorkoutCount == 0)
    }

    @Test func completedTodayCountsDeletedAndBoundary() throws {
        let today = session(end: now)
        _ = session(title: "Gone", end: now, deleted: true)
        _ = session(title: "Yesterday", end: cal.startOfDay(for: now).addingTimeInterval(-1))
        _ = session(title: "Active", end: nil)
        let all = try context.fetch(FetchDescriptor<WorkoutSession>())
        let snap = TodayHeroActivityPresenter.make(sessions: all, scheduled: [], now: now, calendar: cal)
        #expect(snap.completedToday.first?.title == today.title)
        #expect(snap.completedToday.first?.setCount == 1)
        #expect(snap.completedToday.first?.exercises == [TodayHero.Line(name: "Bench", detail: "1 × 5")])
        // Deleted excluded; the rest (including the active session) have sets.
        #expect(snap.completedWorkoutCount == 3)
    }

    @Test func partnerSetsExcludedFromOwnerSummary() throws {
        _ = session(end: now, sets: [("Bench", 5, false, true), ("Bench", 8, false, false)])
        let all = try context.fetch(FetchDescriptor<WorkoutSession>())
        let snap = TodayHeroActivityPresenter.make(sessions: all, scheduled: [], now: now, calendar: cal)
        #expect(snap.completedToday.first?.setCount == 1)
        #expect(snap.completedToday.first?.exercises.first?.detail == "1 × 5")
    }

    @Test func doneTodayIncludesStrengthAndCardio() throws {
        _ = session(title: "Lift", end: now)
        let run = CardioWorkout(type: .run, start: now.addingTimeInterval(300),
                                end: now.addingTimeInterval(1_500), distance: 5_000)
        context.insert(run)

        let strength = try context.fetch(FetchDescriptor<WorkoutSession>())
        let cardio = try context.fetch(FetchDescriptor<CardioWorkout>())
        let snapshot = TodayHeroActivityPresenter.make(
            sessions: strength, cardio: cardio, scheduled: [], now: now, calendar: cal)

        #expect(snapshot.completedToday.map(\.title) == ["Run", "Lift"])
        let summary = try #require(snapshot.daySummary())
        #expect(summary.title == "2 workouts complete")
        #expect(summary.setCount == 1)
        #expect(summary.durationMinutes == 80)
        #expect(summary.exercises.contains(TodayHero.Line(name: "Run", detail: "5.0 km · 20 min")))
        #expect(summary.exercises.contains(TodayHero.Line(name: "Bench", detail: "1 × 5")))
    }

    @Test func scheduledTodayNextAndDeleted() throws {
        let startOfToday = cal.startOfDay(for: now)
        _ = try scheduled(startOfToday.addingTimeInterval(7 * 3_600), title: "Today")
        _ = try scheduled(startOfToday.addingTimeInterval(2 * 86_400), title: "Later")
        _ = try scheduled(startOfToday.addingTimeInterval(86_400), title: "Tomorrow")
        _ = try scheduled(startOfToday.addingTimeInterval(8 * 3_600), title: "Deleted", deleted: true)
        let rows = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let snap = TodayHeroActivityPresenter.make(sessions: [], scheduled: rows, now: now, calendar: cal)
        #expect(snap.todayScheduled?.title == "Today")
        #expect(snap.todayScheduled?.exercises == [TodayHero.Line(name: "Squat", detail: "1 × 5")])
        #expect(snap.todayScheduled?.durationMinutes != nil)
        #expect(snap.remainingScheduledToday == 1)
        #expect(snap.nextScheduled?.title == "Tomorrow")
    }

    @Test func durationSamplesMatchHistoryEstimate() throws {
        for i in 0..<3 { _ = session(title: "S\(i)", end: now.addingTimeInterval(Double(-i) * 86_400)) }
        let all = try context.fetch(FetchDescriptor<WorkoutSession>())
        let plan = plan("P")
        let snap = TodayHeroActivityPresenter.make(sessions: all, scheduled: [], now: now, calendar: cal)
        #expect(snap.suggestedDurationMinutes(plan: plan) ==
                       WorkoutDurationEstimator.estimate(plan: plan, history: all)?.minutes)
    }

    @Test func snapshotDrivesHeroWithoutHistoryAndNeverFalseRecovery() {
        let snap = TodayHeroActivityPresenter.make(sessions: [], scheduled: [], now: now, calendar: cal)
        let hero = TodayHeroPresenter.hero(
            inProgress: nil, scheduled: snap.todayScheduled?.makeHero(), suggested: nil,
            completedWorkoutCount: snap.completedWorkoutCount, completedToday: snap.daySummary(),
            remainingScheduledToday: snap.remainingScheduledToday)
        // Day-one install: no starter plan yet means the hero is loading, never recovery.
        #expect(hero.kind == .loading)
    }
}
#endif
