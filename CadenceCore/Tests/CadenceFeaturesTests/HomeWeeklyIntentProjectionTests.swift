#if canImport(SwiftData)
import XCTest
import SwiftData
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadencePhoneFeatures

@MainActor
final class HomeWeeklyIntentProjectionTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    func testCardioMatchesWeeklyCardioAggregator() throws {
        let ctx = try makeContext()
        let weekStart = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let now = weekStart.addingTimeInterval(3 * 86_400)
        _ = try WorkoutRepository.saveLoggedCardio(type: .run, start: weekStart.addingTimeInterval(-3600), durationSeconds: 1200, in: ctx)
        _ = try WorkoutRepository.saveLoggedCardio(type: .run, start: weekStart.addingTimeInterval(3600), durationSeconds: 1800, in: ctx)
        let all = try WorkoutRepository.allCardio(ctx)
        let snap = HomeWeeklyIntentProjection.make(sessions: [], cardio: all, weekStart: weekStart,
                                                   now: now, cardioProfile: nil)
        let inWeek = all.filter { $0.start >= weekStart }
        XCTAssertEqual(snap.cardio, WeeklyCardioAggregator.summarize(inWeek, since: weekStart, profile: nil))
    }

    func testSetsExcludeOutOfWeekAndWarmupSets() throws {
        let ctx = try makeContext()
        let weekStart = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let now = weekStart.addingTimeInterval(3 * 86_400)
        let old = try WorkoutRepository.createSession(title: "old", date: weekStart.addingTimeInterval(-86_400), in: ctx)
        let cur = try WorkoutRepository.createSession(title: "cur", date: weekStart.addingTimeInterval(86_400), in: ctx)
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        guard let (group, credit) = ex.volumeCredits.first(where: { $0.value > 0 }) else {
            return XCTFail("exercise has no volume credits")
        }
        _ = try WorkoutRepository.addSet(to: old, exercise: ex, weightKg: 50, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: cur, exercise: ex, weightKg: 50, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: cur, exercise: ex, weightKg: 20, reps: 5, isWarmup: true, in: ctx)
        let snap = HomeWeeklyIntentProjection.make(
            sessions: [old, cur], cardio: [], weekStart: weekStart, now: now, cardioProfile: nil)
        XCTAssertEqual(snap.setsByMuscle[group.rawValue], credit)
    }

    func testWeekKeyStableAndDistinct() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let a = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let k = HomeWeeklyIntentSnapshot.weekKey(for: a, calendar: cal)
        XCTAssertEqual(k, HomeWeeklyIntentSnapshot.weekKey(for: a, calendar: cal))
        XCTAssertNotEqual(k, HomeWeeklyIntentSnapshot.weekKey(for: a.addingTimeInterval(7 * 86_400), calendar: cal))
    }
}
#endif
