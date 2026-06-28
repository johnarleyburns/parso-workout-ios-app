import XCTest
import SwiftData
@testable import CadenceCore

/// feedback batch 3 — Home weekly tiles (cardio minutes, volume, body-part coverage).
final class WeeklyStatsTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    func testCardioMinutesSumsLastSevenDays() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let recent = CardioWorkout(type: .run, start: now.addingTimeInterval(-3600),
                                   end: now.addingTimeInterval(-3600 + 1800)) // 30 min
        let stale = CardioWorkout(type: .walk, start: now.addingTimeInterval(-10 * 86_400),
                                  end: now.addingTimeInterval(-10 * 86_400 + 3600)) // 60 min, > 7d ago
        let since = now.addingTimeInterval(-7 * 86_400)  // genuine trailing 7 days
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

    func testWeekStartIsMondayMidnight() {
        let cal = Calendar.current
        // Pick a known Friday at 3pm
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 6  // Friday
        comps.hour = 15
        comps.minute = 30
        guard let friday = cal.date(from: comps) else { XCTFail("Could not build Friday date"); return }

        let start = WeeklyStats.weekStart(now: friday)
        let dayComp = cal.component(.weekday, from: start)
        let hourComp = cal.component(.hour, from: start)
        XCTAssertEqual(dayComp, 2, "weekStart should be Monday (weekday 2), got \(dayComp)")
        XCTAssertEqual(hourComp, 0, "weekStart should be midnight")
        XCTAssertLessThanOrEqual(start, friday, "weekStart should be before or equal to now")
    }

    func testWeekStartOnMondayIsSameDay() {
        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 2  // Monday
        comps.hour = 6
        comps.minute = 0
        guard let monday = cal.date(from: comps) else { XCTFail("Could not build Monday date"); return }

        let start = WeeklyStats.weekStart(now: monday)
        let startDay = cal.startOfDay(for: start)
        let mondayStart = cal.startOfDay(for: monday)
        XCTAssertEqual(startDay, mondayStart, "On Monday 6am, weekStart should be the same Monday at midnight")
    }
}
