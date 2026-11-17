import CadenceFeatures
import Foundation
import CadenceCore

/// Home's weekly rings (strength sets, cardio minutes), computed from a
/// date-bounded fetch rather than the user's full history.
public struct HomeWeeklyIntentSnapshot: Codable, Equatable, Sendable {
    public var weekKey: String
    /// Keyed by `MuscleGroup.rawValue`.
    public var setsByMuscle: [String: Double]
    public var cardio: WeeklyCardioSummary

    public init(weekKey: String, setsByMuscle: [String: Double], cardio: WeeklyCardioSummary) {
        self.weekKey = weekKey
        self.setsByMuscle = setsByMuscle
        self.cardio = cardio
    }

    /// Alias for render paths that must not mention persistence-ish names.
    public var weeklyCardioSummary: WeeklyCardioSummary { cardio }

    public static func weekKey(for weekStart: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: weekStart)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Pure projection scoped to `weekStart...now`; mirrors TrainingFacts' owner
/// working-set filter without its all-time scans.
public enum HomeWeeklyIntentProjection {
    public static func make(sessions: [WorkoutSession], cardio: [CardioWorkout],
                            weekStart: Date, now: Date,
                            cardioProfile: CardioIntensityProfile?) -> HomeWeeklyIntentSnapshot {
        var setsByGroup: [MuscleGroup: Double] = [:]
        for session in sessions
        where session.deletedAt == nil && session.date >= weekStart && session.date <= now {
            for set in session.orderedSets where !set.isWarmup && set.isOwnerSet && set.reps > 0 {
                guard let exercise = set.exercise else { continue }
                for (group, credit) in exercise.volumeCredits where credit > 0 {
                    setsByGroup[group, default: 0] += credit
                }
            }
        }
        let weekCardio = cardio.filter { $0.deletedAt == nil && $0.start >= weekStart && $0.start <= now }
        let weekSessions = sessions.filter { $0.deletedAt == nil && $0.date >= weekStart && $0.date <= now }
        // Same inputs the full Home projection feeds the aggregator, so the
        // two paths never publish different cardio numbers.
        let summary = WeeklyCardioAggregator.summarize(
            weekCardio, since: weekStart, profile: cardioProfile, sessions: weekSessions)
        return HomeWeeklyIntentSnapshot(
            weekKey: HomeWeeklyIntentSnapshot.weekKey(for: weekStart),
            setsByMuscle: Dictionary(uniqueKeysWithValues: setsByGroup.map { ($0.key.rawValue, $0.value) }),
            cardio: summary)
    }
}

/// Durable, actor-isolated cache of the last-computed weekly-intent snapshot.
public actor HomeWeeklyIntentCacheStore {
    private struct Envelope: Codable { var snapshot: HomeWeeklyIntentSnapshot }
    private let fileURL: URL?
    private var memory: Envelope?
    private var memoryLoaded = false

    public init(fileURL: URL?) { self.fileURL = fileURL }

    public static func defaultFileURL() -> URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent("HomeWeeklyIntent.v1.json")
    }

    public func peek() -> HomeWeeklyIntentSnapshot? {
        loadEnvelope()?.snapshot
    }

    @discardableResult
    public func save(_ snapshot: HomeWeeklyIntentSnapshot) -> Bool {
        let env = Envelope(snapshot: snapshot)
        guard let fileURL else { memory = env; memoryLoaded = true; return true }
        guard let data = try? JSONEncoder().encode(env) else { return false }
        do {
            try data.write(to: fileURL, options: .atomic)
            memory = env
            memoryLoaded = true
            return true
        } catch { return false }
    }

    private func loadEnvelope() -> Envelope? {
        if memoryLoaded { return memory }
        memoryLoaded = true
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let env = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        memory = env
        return env
    }
}
