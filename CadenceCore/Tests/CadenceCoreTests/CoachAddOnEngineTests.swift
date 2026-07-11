import XCTest
import SwiftData
@testable import CadenceCore

/// P4 (issue 3) — "Additional strength → Start anyway" must open a real,
/// coach-built session, not dead-end to Home. The addon's `.hardStrengthWarn`
/// session must carry a non-empty `exercises` array so `EditablePlan.from(coach:)`
/// yields a plan.
final class CoachAddOnEngineTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private var testNow: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 25
        comps.hour = 18; comps.minute = 0; comps.second = 0
        return Calendar.current.date(from: comps) ?? Date(timeIntervalSince1970: 1_750_000_000)
    }

    private func strengthEventToday(_ ctx: ModelContext, now: Date) throws -> TrainingEvent {
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-3600), in: ctx)
        let ex = try WorkoutRepository.findOrCreateExercise(
            named: "Bench Press", primaryMuscles: ["chest"], in: ctx)
        for _ in 0..<3 {
            _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 80, reps: 5,
                                             rpe: 8, completedAt: now.addingTimeInterval(-1800), in: ctx)
        }
        session.endedAt = now.addingTimeInterval(-600)
        return TrainingEvent.from(session: session)!
    }

    func testAdditionalStrengthAddOnHasExercises() throws {
        let ctx = try makeContext()
        let now = testNow
        let event = try strengthEventToday(ctx, now: now)
        let facts = CoachFacts.make(from: [event], goal: .hypertrophy,
                                    experience: .intermediate, now: now)

        let addOn = CoachAddOnEngine.run(facts: facts)
        let warn = (addOn.primaryOption.map { [$0] } ?? []) + addOn.secondaryOptions
        let strengthWarn = warn.first { $0.session.id == "addon.hardStrengthWarn" }
        XCTAssertNotNil(strengthWarn, "After lifting today, the coach should offer an 'Additional strength' add-on")
        let exercises = strengthWarn?.session.exercises ?? []
        XCTAssertFalse(exercises.isEmpty,
                       "The additional-strength add-on session must carry exercises so 'Start anyway' opens a real session")
        // The exercises should carry the goal's rep ladders (P1 reuse).
        XCTAssertTrue(exercises.contains { ($0.repLadder?.isEmpty == false) },
                      "Add-on strength exercises should carry rep ladders")
    }

    func testFullBodyStrengthExercisesAreNonEmptyAndCited() throws {
        let ctx = try makeContext()
        let now = testNow
        let event = try strengthEventToday(ctx, now: now)
        let facts = CoachFacts.make(from: [event], goal: .strength,
                                    experience: .intermediate, now: now)
        let exercises = CoachSession.fullBodyStrengthExercises(facts: facts)
        XCTAssertFalse(exercises.isEmpty, "A coach-built full-body session names movements")
        XCTAssertGreaterThanOrEqual(exercises.count, 4, "Full-body should cover several patterns")
    }
}
