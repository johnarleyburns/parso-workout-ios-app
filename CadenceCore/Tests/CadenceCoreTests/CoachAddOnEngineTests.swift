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

    // MARK: - Same-day load awareness (coach-user-control Phase 2)

    private func cardioEventToday(_ ctx: ModelContext, type: CardioType, now: Date,
                                  hoursAgo: Double, minutes: Double = 30,
                                  avgHR: Double? = nil, maxHR: Double? = nil,
                                  age: Int? = 50) throws -> TrainingEvent {
        let start = now.addingTimeInterval(-hoursAgo * 3600)
        let cardio = CardioWorkout(type: type, start: start,
                                   end: start.addingTimeInterval(minutes * 60),
                                   avgHeartRate: avgHR, maxHeartRate: maxHR, source: .iphone)
        ctx.insert(cardio)
        try ctx.save()
        return TrainingEvent.from(cardio: cardio, userAge: age)
    }

    /// After HIIT + boxing today, "Add easy cardio" must not be pushed — the
    /// intense load is already banked (user decision: notice it, stop nagging).
    func testNoEasyCardioAddOnAfterIntenseCardioToday() throws {
        let ctx = try makeContext()
        let now = testNow
        let hiit = try cardioEventToday(ctx, type: .hiit, now: now, hoursAgo: 6)
        let boxing = try cardioEventToday(ctx, type: .boxing, now: now, hoursAgo: 3,
                                          avgHR: 139, maxHR: 170)
        let facts = CoachFacts.make(from: [hiit, boxing], goal: .hypertrophy,
                                    experience: .intermediate, now: now)

        let addOn = CoachAddOnEngine.run(facts: facts)
        XCTAssertNil(addOn.primaryOption,
                     "No encouraged easy-cardio add-on after intense same-day cardio")
        let all = (addOn.primaryOption.map { [$0] } ?? []) + addOn.secondaryOptions
        XCTAssertFalse(all.contains { $0.id == "addon.encouragedCardio" })
        XCTAssertFalse(all.contains { $0.id == "addon.neutralMovement" })
    }

    /// Two easier cardio sessions on the same day also stop the easy-cardio push
    /// even when neither classifies vigorous.
    func testNoEasyCardioAddOnAfterTwoCardioSessionsToday() throws {
        let ctx = try makeContext()
        let now = testNow
        let walk1 = try cardioEventToday(ctx, type: .walk, now: now, hoursAgo: 8, avgHR: 95, maxHR: 105)
        let walk2 = try cardioEventToday(ctx, type: .walk, now: now, hoursAgo: 2, avgHR: 96, maxHR: 104)
        let facts = CoachFacts.make(from: [walk1, walk2], goal: .hypertrophy,
                                    experience: .intermediate, now: now)

        let addOn = CoachAddOnEngine.run(facts: facts)
        let all = (addOn.primaryOption.map { [$0] } ?? []) + addOn.secondaryOptions
        XCTAssertFalse(all.contains { $0.id == "addon.encouragedCardio" })
    }
}
