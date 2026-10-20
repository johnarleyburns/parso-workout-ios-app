import Foundation
import CadenceCore
import Observation

/// "Send Workout to Watch": workouts designed on the iPhone (strength or cardio) that wait on the
/// Watch as "Sent from your phone" until the user starts them. Once started, a workout leaves this
/// list for good — it is then a normal unfinished or completed workout on the Watch.
public enum WatchSentWorkouts {
    /// Most workouts kept on the Watch at once; the oldest are dropped first.
    public static let limit = 10

    /// A strength workout from an editable plan. Rep ladder and names keep older Watches working.
    public static func strengthSession(id: UUID = UUID(), title: String,
                                       exercises: [(name: String, repTargets: [Int])],
                                       planPayload: WatchPlanPayload? = nil) -> WatchSync.TodayPlan.Session {
        WatchSync.TodayPlan.Session(
            id: id.uuidString,
            kind: .strength,
            label: title,
            exerciseNames: exercises.map(\.name),
            repLadder: exercises.first?.repTargets ?? [],
            planPayload: planPayload)
    }

    public static func cardioSession(id: UUID = UUID(), title: String, cardioType: String,
                                     durationMinutes: Int?, zone: Int? = nil) -> WatchSync.TodayPlan.Session {
        WatchSync.TodayPlan.Session(
            id: id.uuidString,
            kind: .cardio,
            label: title,
            cardioType: cardioType,
            durationMinutes: durationMinutes,
            zone: zone)
    }

    /// Adds (or replaces, by id) a sent workout, newest last, capped at `limit`.
    public static func adding(_ session: WatchSync.TodayPlan.Session,
                              to existing: [WatchSync.TodayPlan.Session]) -> [WatchSync.TodayPlan.Session] {
        var result = existing.filter { $0.id != session.id && !$0.isRest }
        result.append(session)
        return Array(result.suffix(limit))
    }

    /// Sent workouts the user has not started yet.
    public static func pending(_ sent: [WatchSync.TodayPlan.Session],
                               consumedIDs: Set<String>) -> [WatchSync.TodayPlan.Session] {
        sent.filter { !consumedIDs.contains($0.id) && !$0.isRest }
    }

    public static func contextDict(_ sessions: [WatchSync.TodayPlan.Session]) -> [String: Any] {
        [WatchSync.Key.sentWorkouts: WatchSync.TodayPlan.rows(sessions)]
    }

    public static func sessions(from context: [String: Any]) -> [WatchSync.TodayPlan.Session] {
        guard let rows = context[WatchSync.Key.sentWorkouts] as? [[String: Any]] else { return [] }
        return WatchSync.TodayPlan.sessions(fromRows: rows)
    }
}

/// Watch-side state for workouts sent from the iPhone. Started workouts are remembered across
/// launches so they never reappear; a started lift is then a normal unfinished workout, a finished
/// one lives in history.
@MainActor @Observable
public final class WatchSentWorkoutStore {
    public static let shared = WatchSentWorkoutStore()
    private static let consumedKey = "watch.sentWorkouts.consumed"

    public var sentWorkouts: [WatchSync.TodayPlan.Session] = []
    public private(set) var consumedIDs: Set<String>
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        consumedIDs = Set(defaults.stringArray(forKey: Self.consumedKey) ?? [])
    }

    public var pending: [WatchSync.TodayPlan.Session] {
        WatchSentWorkouts.pending(sentWorkouts, consumedIDs: consumedIDs)
    }

    public func markStarted(_ id: String) {
        consumedIDs.insert(id)
        defaults.set(Array(consumedIDs), forKey: Self.consumedKey)
    }
}
