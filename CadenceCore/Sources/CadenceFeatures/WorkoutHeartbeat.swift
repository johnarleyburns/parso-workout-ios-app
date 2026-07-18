import Foundation

/// A tiny UserDefaults-backed liveness record for the in-progress workout
/// (launch-blockers plan, Phase 1e — crash/upgrade recovery, no schema change).
///
/// All sets are already durable in SwiftData; what dies with the process is the
/// in-memory `ActiveWorkoutModel` + its clock. The heartbeat is written on the
/// 5 s session tick and on scene transitions, and cleared on explicit
/// end/discard. On relaunch it lets recovery reconstruct the clock with the
/// dead gap [lastAlive, now] excluded from elapsed time.
public struct WorkoutHeartbeat: Equatable, Codable, Sendable {
    public var sessionID: UUID
    /// The last moment the app was known alive with this workout active.
    public var lastAlive: Date
    /// Active (unpaused) elapsed seconds as of `lastAlive`.
    public var elapsed: TimeInterval
    /// Whether the clock was paused at `lastAlive`.
    public var isPaused: Bool

    public init(sessionID: UUID, lastAlive: Date, elapsed: TimeInterval, isPaused: Bool) {
        self.sessionID = sessionID
        self.lastAlive = lastAlive
        self.elapsed = elapsed
        self.isPaused = isPaused
    }
}

public enum WorkoutHeartbeatStore {
    public static let key = "cadence.workoutHeartbeat"

    public static func write(_ heartbeat: WorkoutHeartbeat, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(heartbeat) else { return }
        defaults.set(data, forKey: key)
    }

    public static func read(defaults: UserDefaults = .standard) -> WorkoutHeartbeat? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WorkoutHeartbeat.self, from: data)
    }

    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
