import Foundation
import CadenceCore

/// Deterministic in-memory health provider for previews and UI tests (FR-3,
/// FR-2.1, FR-4). The simulator has no real Health data, so UI tests inject
/// this to get stable, assertable values.
final class FakeHealthProvider: HealthDataProviding, @unchecked Sendable {
    var isHealthDataAvailable: Bool { true }
    var authStatus: HealthAuthorizationStatus = .notDetermined
    var seededTodaySteps = 7432
    private let calendar = Calendar.current

    func requestAuthorization() async -> HealthAuthorizationStatus {
        authStatus = .authorized
        return authStatus
    }

    func todayActivity() async -> DayActivity {
        DayActivity(date: calendar.startOfDay(for: Date()), steps: seededTodaySteps,
                    distanceMeters: Double(seededTodaySteps) * 0.78,
                    flightsClimbed: 8, activeEnergyKcal: 540)
    }

    func activityTrend(days: Int) async -> [DayActivity] {
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
    var pendingWorkouts: [IngestedWorkout] = [
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

    func newWorkouts(since: Date?) async -> [IngestedWorkout] { pendingWorkouts }

    var savedSummaries: [StrengthWorkoutSummary] = []
    func saveStrengthWorkout(_ summary: StrengthWorkoutSummary) async -> UUID? {
        savedSummaries.append(summary)
        return summary.id
    }

    var savedCardio: [CardioWorkoutSummary] = []
    func saveCardioWorkout(_ summary: CardioWorkoutSummary) async -> UUID? {
        savedCardio.append(summary)
        return summary.id
    }
}
