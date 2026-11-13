import Foundation
import CadenceCore

/// Projects a user's manually scheduled workout (`ScheduledWorkout`) into the Watch
/// "today" shape so a schedule the user set themselves shows on Watch Today too,
/// not only the coach's automated suggestion (`CoachWatchTodayBridge`).
///
/// Pure and headlessly testable: no SwiftData dependency. `CoachWatchTodayBridge`
/// stays untouched; this is a separate, additive concern layered on top via `merge`.
public enum ScheduledWorkoutWatchBridge {
    /// A flattened, Sendable view of the `ScheduledWorkout` fields this bridge needs,
    /// so callers never have to hand a SwiftData model across an isolation boundary.
    public struct Input: Sendable {
        public var id: UUID
        public var date: Date
        public var title: String
        public var payloadData: Data
        public var payloadVersion: Int
        public var status: ScheduledWorkoutStatus

        public init(id: UUID, date: Date, title: String, payloadData: Data,
                    payloadVersion: Int, status: ScheduledWorkoutStatus) {
            self.id = id
            self.date = date
            self.title = title
            self.payloadData = payloadData
            self.payloadVersion = payloadVersion
            self.status = status
        }
    }

    /// One Watch session for a single scheduled workout, or nil if its payload can't be decoded.
    /// Mirrors `HomePlannedWorkoutsSection.item(_:)`'s exact decode branching: try the cardio
    /// decode first, then the strength plan decode, else give up.
    public static func session(id: UUID, title: String, payloadData: Data,
                               payloadVersion: Int) -> WatchSync.TodayPlan.Session? {
        if let cardioType = try? ScheduledWorkoutStore.decodeCardioType(payloadData, version: payloadVersion) {
            return WatchSentWorkouts.cardioSession(id: id, title: title,
                                                   cardioType: cardioType.rawValue,
                                                   durationMinutes: nil, zone: nil)
        }
        if let plan = try? ScheduledWorkoutStore.decode(payloadData, version: payloadVersion) {
            let exercises = plan.exercises.map { (name: $0.name, repTargets: $0.sets.map(\.targetReps)) }
            return WatchSentWorkouts.strengthSession(id: id, title: title, exercises: exercises,
                                                     planPayload: nil)
        }
        return nil
    }

    /// Today's visible scheduled workouts, mapped to Watch sessions. Reuses the same
    /// same-day + not-cancelled/not-completed visibility rule as
    /// `PlannedWorkoutsPresenter.today` (that rule is `private` there, so this is an
    /// accepted, intentional small duplication rather than an oversight).
    public static func todaySessions(_ inputs: [Input], now: Date = Date(),
                                     calendar: Calendar = .current) -> [WatchSync.TodayPlan.Session] {
        inputs
            .filter { calendar.isDate($0.date, inSameDayAs: now)
                && $0.status != .cancelled && $0.status != .completed }
            .compactMap { session(id: $0.id, title: $0.title, payloadData: $0.payloadData,
                                   payloadVersion: $0.payloadVersion) }
    }

    /// Scheduled sessions are prepended ahead of the coach's sessions, so
    /// `WatchTodayRecommendations`'s "first session wins per kind" rule makes the
    /// user's own schedule win same-kind ties, while a coach suggestion of a
    /// *different* modality still surfaces as a second row (not suppressed) —
    /// NFR-8, "the coach suggests, it does not proscribe".
    public static func merge(scheduledSessions: [WatchSync.TodayPlan.Session],
                             into base: WatchSync.TodayPlan) -> WatchSync.TodayPlan {
        WatchSync.TodayPlan(sessions: scheduledSessions + base.sessions, updatedAt: base.updatedAt)
    }
}
