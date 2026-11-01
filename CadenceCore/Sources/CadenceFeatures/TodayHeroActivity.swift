import Foundation
import CadenceCore

/// Display-ready scheduled workout values; never a managed model or plan.
public struct ScheduledHeroSnapshot: Sendable, Equatable {
    public let title: String
    public let date: Date
    public let exercises: [TodayHero.Line]
    public let durationMinutes: Int?

    public init(title: String, date: Date, exercises: [TodayHero.Line], durationMinutes: Int?) {
        self.title = title; self.date = date; self.exercises = exercises
        self.durationMinutes = durationMinutes
    }

    public func makeHero() -> TodayHero {
        TodayHero(kind: .scheduled, title: title, estimatedMinutes: durationMinutes,
                  exercises: exercises, reason: nil)
    }
}

/// Value-only history facts for the Today hero, built off the main actor.
public struct TodayHeroActivitySnapshot: Sendable, Equatable {
    public struct CompletedWorkout: Sendable, Equatable {
        public let title: String
        public let setCount: Int
        public let volumeKg: Double
        public let durationMinutes: Int?
        public let exercises: [TodayHero.Line]
        public init(title: String, setCount: Int, volumeKg: Double,
                    durationMinutes: Int?, exercises: [TodayHero.Line]) {
            self.title = title; self.setCount = setCount; self.volumeKg = volumeKg
            self.durationMinutes = durationMinutes; self.exercises = exercises
        }
    }

    /// False until the background projection has published; callers must not
    /// treat the empty values as "no history".
    public let isLoaded: Bool
    public let completedWorkoutCount: Int
    public let completedToday: CompletedWorkout?
    public let nextScheduled: ScheduledHeroSnapshot?
    public let todayScheduled: ScheduledHeroSnapshot?
    public let remainingScheduledToday: Int
    /// Per-set work-second samples for duration estimates of in-memory plans.
    public let durationSamples: [Double]

    public init(isLoaded: Bool = true, completedWorkoutCount: Int,
                completedToday: CompletedWorkout?, nextScheduled: ScheduledHeroSnapshot?,
                todayScheduled: ScheduledHeroSnapshot?, remainingScheduledToday: Int,
                durationSamples: [Double]) {
        self.isLoaded = isLoaded
        self.completedWorkoutCount = completedWorkoutCount
        self.completedToday = completedToday
        self.nextScheduled = nextScheduled
        self.todayScheduled = todayScheduled
        self.remainingScheduledToday = remainingScheduledToday
        self.durationSamples = durationSamples
    }

    public static let empty = TodayHeroActivitySnapshot(
        isLoaded: false, completedWorkoutCount: 0, completedToday: nil, nextScheduled: nil,
        todayScheduled: nil, remainingScheduledToday: 0, durationSamples: [])

    public func daySummary() -> DaySummary? {
        completedToday.map {
            DaySummary(title: $0.title, setCount: $0.setCount, volumeKg: $0.volumeKg,
                       durationMinutes: $0.durationMinutes, nextSessionTitle: nextScheduled?.title,
                       nextSessionDate: nextScheduled?.date, exercises: $0.exercises)
        }
    }

    public func suggestedDurationMinutes(plan: EditablePlan) -> Int? {
        WorkoutDurationEstimator.estimate(plan: plan, workSecondsSamples: durationSamples)?.minutes
    }
}

public enum TodayHeroActivityPresenter {
    public static func heroLines(_ plan: EditablePlan?) -> [TodayHero.Line] {
        plan?.exercises.map {
            TodayHero.Line(name: $0.name, detail: "\($0.sets.count) × \($0.sets.first?.targetReps ?? 0)")
        } ?? []
    }

    /// Runs on a background context; every read of a model happens here.
    public static func make(sessions: [WorkoutSession], scheduled: [ScheduledWorkout],
                            now: Date, calendar: Calendar = .current) -> TodayHeroActivitySnapshot {
        let samples = WorkoutDurationEstimator.workSecondsSamples(from: sessions)
        let today = calendar.startOfDay(for: now)
        let completed = sessions
            .filter { s in
                s.deletedAt == nil && s.endedAt != nil && s.hasSets
                    && calendar.isDate(s.endedAt ?? s.date, inSameDayAs: today)
            }
            .sorted { ($0.endedAt ?? $0.date) > ($1.endedAt ?? $1.date) }
            .first
            .map(completedWorkout)
        let visible = scheduled.filter(\.isVisible)
        let todayRows = visible.filter { calendar.isDate($0.scheduledDate, inSameDayAs: now) }
        func snapshot(_ row: ScheduledWorkout) -> ScheduledHeroSnapshot {
            let plan = try? ScheduledWorkoutStore.decode(row.payloadData, version: row.payloadVersion)
            return ScheduledHeroSnapshot(
                title: row.title, date: row.scheduledDate, exercises: heroLines(plan),
                durationMinutes: WorkoutDurationEstimator.estimate(plan: plan, workSecondsSamples: samples)?.minutes)
        }
        let next = visible
            .filter { $0.scheduledDate >= today && !calendar.isDate($0.scheduledDate, inSameDayAs: now) }
            .sorted { $0.scheduledDate < $1.scheduledDate }
            .first
        return TodayHeroActivitySnapshot(
            isLoaded: true,
            completedWorkoutCount: sessions.filter { $0.hasSets && $0.deletedAt == nil }.count,
            completedToday: completed,
            nextScheduled: next.map { ScheduledHeroSnapshot(title: $0.title, date: $0.scheduledDate,
                                                            exercises: [], durationMinutes: nil) },
            todayScheduled: todayRows.first.map(snapshot),
            remainingScheduledToday: todayRows.count,
            durationSamples: samples)
    }

    private static func completedWorkout(_ session: WorkoutSession) -> TodayHeroActivitySnapshot.CompletedWorkout {
        let sets = session.orderedSets
        let lines: [TodayHero.Line] = session.exercisesInOrder.map { ex in
            let working = sets.filter { $0.exercise?.id == ex.id && !$0.isWarmup && $0.isOwnerSet }
            let detail: String
            if working.isEmpty {
                detail = String(localized: "No sets", bundle: .module)
            } else if let lastReps = working.last?.reps {
                detail = "\(working.count) × \(lastReps)"
            } else {
                detail = "\(working.count) sets"
            }
            return TodayHero.Line(name: ex.name, detail: detail)
        }
        let duration = session.duration
        return .init(title: session.title.isEmpty ? String(localized: "Workout complete", bundle: .module) : session.title,
                     setCount: sets.filter { !$0.isWarmup && $0.isOwnerSet }.count,
                     volumeKg: session.totalVolume,
                     durationMinutes: duration > 0 ? Int((duration / 60).rounded()) : nil,
                     exercises: lines)
    }
}
