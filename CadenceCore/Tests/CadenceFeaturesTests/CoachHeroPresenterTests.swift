import XCTest
import SwiftData
import CadenceCore
@testable import CadenceFeatures

/// Phase B (field-test-fixes): hero copy from logged work, not planned candidates.
final class CoachHeroPresenterTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private var today: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 7; c.day = 18
        c.hour = 10; c.minute = 0; c.second = 0
        return Calendar.current.date(from: c) ?? Date()
    }

    /// Completed strength session's exercise names, deduped in first-seen order.
    private func loggedExerciseNames(from events: [TrainingEvent]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let strengthEvents = events.filter(\.isStrength).sorted(by: { $0.end > $1.end })
        for event in strengthEvents {
            guard case .strength(let d) = event.kind, let details = d else { continue }
            for ex in details.exercises where seen.insert(ex.exerciseName).inserted {
                result.append(ex.exerciseName)
            }
        }
        return result
    }

    // MARK: - Bug reproduction: deferred-candidate exercise names are NOT "logged"

    func testDeferredCandidatesDoNotProduceLoggedExercises() throws {
        // Bug: the old code took exercise names from deferred planned candidates,
        // producing "Air Squat and Air Squat logged" when two deferred candidates
        // both started with Air Squat and nothing was actually completed.
        // The fix: check `hasTodayStrengthCompleted` (from actual completed events),
        // not deferred candidates.
        let hero = CoachHeroPresenter.present(
            primaryKind: .rest,
            primaryTitle: "Rest day",
            primarySubtitle: "",
            todayPlannedCount: 0,
            isCompleteState: false,
            planAdherenceCompletedKind: nil,
            completedDescription: nil,
            recentFactText: "",
            hasTodayStrengthCompleted: false,
            todayLoggedExerciseNames: []
        )

        // Nothing was completed today → should NOT say "Strength is done today"
        XCTAssertNotEqual(hero.title, "Strength is done today")
        // Should NOT contain exercise names
        XCTAssertFalse(hero.subtitle.contains("Air Squat"))
    }

    func testCompletedTodayStrengthShowsExerciseNames() throws {
        let ctx = try makeContext()
        let now = today
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-3600), in: ctx)
        let snatch = try WorkoutRepository.findOrCreateExercise(named: "Snatch", primaryMuscles: ["shoulders"], in: ctx)
        let pulldown = try WorkoutRepository.findOrCreateExercise(named: "Lat Pulldown", primaryMuscles: ["lats"], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: snatch, weightKg: 50, reps: 5, rpe: 8, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: snatch, weightKg: 50, reps: 5, rpe: 8, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: pulldown, weightKg: 60, reps: 8, rpe: 7, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: pulldown, weightKg: 60, reps: 8, rpe: 7, in: ctx)
        session.endedAt = now.addingTimeInterval(-3300)
        try ctx.save()

        let events = [TrainingEvent.from(session: session)!]
        let names = loggedExerciseNames(from: events)

        let hero = CoachHeroPresenter.present(
            primaryKind: .rest,
            primaryTitle: "Rest day",
            primarySubtitle: "",
            todayPlannedCount: 0,
            isCompleteState: false,
            planAdherenceCompletedKind: nil,
            completedDescription: nil,
            recentFactText: "",
            hasTodayStrengthCompleted: true,
            todayLoggedExerciseNames: names
        )

        // Strength done today → title reflects that
        XCTAssertEqual(hero.title, "Strength is done today")
        // Names from completed session, deduped
        XCTAssertTrue(hero.subtitle.contains("Snatch"))
        XCTAssertTrue(hero.subtitle.contains("Lat Pulldown"))
    }

    func testNoDuplicateExerciseNames() throws {
        let ctx = try makeContext()
        let now = today
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-1800), in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(named: "Back Squat", primaryMuscles: ["quadriceps"], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 80, reps: 5, rpe: 8, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 80, reps: 5, rpe: 8, in: ctx)
        session.endedAt = now.addingTimeInterval(-1500)
        try ctx.save()

        let events = [TrainingEvent.from(session: session)!]
        let names = loggedExerciseNames(from: events)

        let hero = CoachHeroPresenter.present(
            primaryKind: .rest,
            primaryTitle: "Rest day",
            primarySubtitle: "",
            todayPlannedCount: 0,
            isCompleteState: false,
            planAdherenceCompletedKind: nil,
            completedDescription: nil,
            recentFactText: "",
            hasTodayStrengthCompleted: true,
            todayLoggedExerciseNames: names
        )

        XCTAssertEqual(hero.title, "Strength is done today")
        // Back Squat should appear exactly once
        let count = hero.subtitle.components(separatedBy: "Back Squat").count - 1
        XCTAssertEqual(count, 1, "Back Squat should appear exactly once, not duplicated")
    }

    func testCompletedTodayStrengthAllowsCardioCard() throws {
        let ctx = try makeContext()
        let now = today
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-3600), in: ctx)
        let dl = try WorkoutRepository.findOrCreateExercise(named: "Deadlift", primaryMuscles: ["hamstrings"], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: dl, weightKg: 120, reps: 5, rpe: 8, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: dl, weightKg: 120, reps: 5, rpe: 8, in: ctx)
        session.endedAt = now.addingTimeInterval(-3300)
        try ctx.save()

        let events = [TrainingEvent.from(session: session)!]
        let names = loggedExerciseNames(from: events)

        let hero = CoachHeroPresenter.present(
            primaryKind: .moderateAerobic,
            primaryTitle: "Moderate Run",
            primarySubtitle: "30 minutes",
            todayPlannedCount: 0,
            isCompleteState: false,
            planAdherenceCompletedKind: nil,
            completedDescription: nil,
            recentFactText: "",
            hasTodayStrengthCompleted: true,
            todayLoggedExerciseNames: names
        )

        // Primary is cardio but strength already done → title names the cardio session
        XCTAssertEqual(hero.title, "Moderate Run")
    }

    func testCompleteStateReturnsCorrectTitle() throws {
        let hero = CoachHeroPresenter.present(
            primaryKind: .rest,
            primaryTitle: "",
            primarySubtitle: "",
            todayPlannedCount: 0,
            isCompleteState: true,
            planAdherenceCompletedKind: .strength,
            completedDescription: "All done for today",
            recentFactText: "",
            hasTodayStrengthCompleted: true,
            todayLoggedExerciseNames: ["Squat"]
        )

        XCTAssertEqual(hero.title, "You put in the work")
        XCTAssertEqual(hero.subtitle, "All done for today")
    }
}
