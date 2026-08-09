import Foundation
import CadenceCore

/// Deterministic in-memory health provider for previews and tests (FR-3, FR-2.1,
/// FR-4). The simulator has no real Health data, so UI tests injected this to get
/// stable, assertable values. Lifted out of the app target's
/// `Services/FakeProviders.swift` so headless `swift test` can use it too.
@MainActor
public final class FakeHealthProvider: HealthDataProviding {
    public var isHealthDataAvailable: Bool { true }
    public var authStatus: HealthAuthorizationStatus = .notDetermined
    public var seededTodaySteps = 7432
    private let calendar = Calendar.current

    public init() {}

    public func requestAuthorization() async -> HealthAuthorizationStatus {
        authStatus = .authorized
        return authStatus
    }

    public func todayActivity() async -> DayActivity {
        DayActivity(date: calendar.startOfDay(for: Date()), steps: seededTodaySteps,
                    distanceMeters: Double(seededTodaySteps) * 0.78,
                    flightsClimbed: 8, activeEnergyKcal: 540)
    }

    public func activityTrend(days: Int) async -> [DayActivity] {
        let base = [6800, 9200, 12010, 7600, 8900, 10450, seededTodaySteps]
        let today = calendar.startOfDay(for: Date())
        return (0..<days).map { i in
            let date = calendar.date(byAdding: .day, value: -(days - 1 - i), to: today)!
            let steps = base[(base.count - days + i + base.count) % base.count]
            return DayActivity(date: date, steps: steps, distanceMeters: Double(steps) * 0.78,
                               flightsClimbed: 3 + i % 6, activeEnergyKcal: 400 + Double(i) * 30)
        }
    }

    /// Returns a fixed Watch-recorded run so ingest (FR-2.1) is testable.
    public var pendingWorkouts: [IngestedWorkout] = [
        IngestedWorkout(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            type: .run,
            start: Date(timeIntervalSinceNow: -3600),
            end: Date(timeIntervalSinceNow: -1800),
            distanceMeters: 5200, activeEnergyKcal: 410,
            avgHeartRate: 148, maxHeartRate: 172, source: .watch,
            hrSamples: (0..<30).map { HRSamplePoint(t: TimeInterval($0 * 60), bpm: 130 + Double($0 % 40)) }
        )
    ]

    public func newWorkouts(since: Date?) async -> [IngestedWorkout] { pendingWorkouts }

    public var savedSummaries: [StrengthWorkoutSummary] = []
    public func saveStrengthWorkout(_ summary: StrengthWorkoutSummary) async -> UUID? {
        savedSummaries.append(summary)
        return summary.id
    }

    public var savedCardio: [CardioWorkoutSummary] = []
    public func saveCardioWorkout(_ summary: CardioWorkoutSummary) async -> UUID? {
        savedCardio.append(summary)
        return summary.id
    }
}
