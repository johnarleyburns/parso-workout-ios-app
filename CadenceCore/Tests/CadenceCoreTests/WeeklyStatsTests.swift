import XCTest
import SwiftData
@testable import CadenceCore

/// feedback batch 3 — Home weekly tiles (cardio minutes, volume, body-part coverage).
final class WeeklyStatsTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    func testCardioMinutesSumsLastSevenDays() throws {
        let now = Date()
        let recent = CardioWorkout(type: .run, start: now.addingTimeInterval(-3600),
                                   end: now.addingTimeInterval(-3600 + 1800)) // 30 min
        let stale = CardioWorkout(type: .walk, start: now.addingTimeInterval(-10 * 86_400),
                                  end: now.addingTimeInterval(-10 * 86_400 + 3600)) // 60 min, > 7d ago
        let since = WeeklyStats.weekStart(now: now)
        XCTAssertEqual(WeeklyStats.cardioMinutes([recent, stale], since: since), 30)
    }

    func testVolumeSumsOwnerWorkingSets() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Push", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, isWarmup: true, in: ctx)
        let since = WeeklyStats.weekStart()
        // Only the working set counts: 100 × 5 = 500.
        XCTAssertEqual(WeeklyStats.volumeKg([session], since: since), 500, accuracy: 0.001)
    }

    func testBodyPartsFromWeeksSessions() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Legs", in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(named: "Back Squat", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 140, reps: 5, in: ctx)
        let since = WeeklyStats.weekStart()
        let (hit, missing) = WeeklyStats.bodyParts([session], since: since)
        // Back Squat primary quads/glutes (legs) + secondary hamstrings/lower-back (back).
        XCTAssertTrue(hit.contains(.legs))
        XCTAssertTrue(hit.contains(.back))
        XCTAssertTrue(missing.contains(.chest))
    }
}
