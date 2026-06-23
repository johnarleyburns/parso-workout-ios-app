import XCTest
import SwiftData
@testable import CadenceCore

final class CoachFactsTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private var testNow: Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 5; comps.hour = 12; comps.minute = 0; comps.second = 0
        return cal.date(from: comps) ?? Date()
    }

    private func makeStrengthEvent(context: ModelContext, name: String, primaryMuscles: [String],
                                    secondaryMuscles: [String] = [], weight: Double, reps: Int, rpe: Double?,
                                    date: Date) throws -> TrainingEvent {
        let session = try WorkoutRepository.createSession(date: date.addingTimeInterval(-600), in: context)
        let ex = try WorkoutRepository.findOrCreateExercise(
            named: name, primaryMuscles: primaryMuscles, secondaryMuscles: secondaryMuscles, in: context)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: weight, reps: reps, rpe: rpe, in: context)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: weight, reps: reps, rpe: rpe, in: context)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: weight, reps: reps, rpe: rpe, in: context)
        session.endedAt = date
        return TrainingEvent.from(session: session)!
    }

    private func makeCardioEvent(context: ModelContext, type: CardioType, start: Date, duration: TimeInterval,
                                  avgHR: Double?) -> TrainingEvent {
        let cardio = CardioWorkout(type: type, start: start, end: start.addingTimeInterval(duration),
                                    avgHeartRate: avgHR, source: .iphone)
        context.insert(cardio)
        return TrainingEvent.from(cardio: cardio)
    }

    // MARK: - Rolling windows

    func testRolling72hWindowIncludesRecentEvents() throws {
        let ctx = try makeContext()
        let now = testNow
        let event = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                           weight: 100, reps: 5, rpe: 8, date: now.addingTimeInterval(-3600))
        let facts = CoachFacts.make(from: [event], goal: .strength, experience: .intermediate, now: now)
        XCTAssertEqual(facts.rolling72hCompletedEvents.count, 1)
    }

    func testRolling72hWindowExcludesOldEvents() throws {
        let ctx = try makeContext()
        let now = testNow
        let event = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                           weight: 100, reps: 5, rpe: 8, date: now.addingTimeInterval(-80 * 3600))
        let facts = CoachFacts.make(from: [event], goal: .strength, experience: .intermediate, now: now)
        XCTAssertEqual(facts.rolling72hCompletedEvents.count, 0)
    }

    func testRolling7dWindowKeepsSundayOnMonday() throws {
        let ctx = try makeContext()
        let now = testNow
        let sundayEvent = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                                 weight: 100, reps: 5, rpe: 8, date: now.addingTimeInterval(-5 * 86400))
        let facts = CoachFacts.make(from: [sundayEvent], goal: .strength, experience: .intermediate, now: now)
        XCTAssertEqual(facts.rolling7dCompletedEvents.count, 1)
    }

    func testEventExactly7dAgoDropsOut() throws {
        let ctx = try makeContext()
        let now = testNow
        let exactEvent = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                                weight: 100, reps: 5, rpe: 8,
                                                date: now.addingTimeInterval(-7 * 86400 - 1))
        let facts = CoachFacts.make(from: [exactEvent], goal: .strength, experience: .intermediate, now: now)
        XCTAssertEqual(facts.rolling7dCompletedEvents.count, 0)
    }

    func testNowIsInjectable() throws {
        let ctx = try makeContext()
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                            weight: 100, reps: 5, rpe: 8,
                                            date: fixedNow.addingTimeInterval(-3600))
        let facts = CoachFacts.make(from: [recent], goal: .strength, experience: .intermediate, now: fixedNow)
        XCTAssertEqual(facts.rolling72hCompletedEvents.count, 1)
    }

    // MARK: - Moderate-equivalent minutes

    func testModerateEquivalentMinutes() throws {
        let ctx = try makeContext()
        let now = testNow
        let run = makeCardioEvent(context: ctx, type: .run, start: now.addingTimeInterval(-7200),
                                   duration: 1800, avgHR: 160)
        let walk = makeCardioEvent(context: ctx, type: .walk, start: now.addingTimeInterval(-3600),
                                    duration: 3600, avgHR: 100)

        let facts = CoachFacts.make(from: [run, walk], goal: .strength, experience: .intermediate, now: now)
        XCTAssertGreaterThan(facts.weeklyBalance.moderateEquivalentMinutes, 0)
        XCTAssertGreaterThan(facts.weeklyBalance.vigorousMinutes, 0)
    }

    func testMissingHRIntensityIsLowConfidence() throws {
        let ctx = try makeContext()
        let now = testNow
        let walk = makeCardioEvent(context: ctx, type: .walk, start: now.addingTimeInterval(-3600),
                                    duration: 1800, avgHR: nil)
        let facts = CoachFacts.make(from: [walk], goal: .strength, experience: .intermediate, now: now)
        XCTAssertEqual(facts.weeklyBalance.dataCompleteness, .moderate)
    }

    // MARK: - Recovery state

    func testRecoveryWindowBlocksExactExercise() throws {
        let ctx = try makeContext()
        let now = testNow
        let event = try makeStrengthEvent(context: ctx, name: "Deadlift", primaryMuscles: ["hamstrings", "lower-back"],
                                           weight: 140, reps: 5, rpe: 9, date: now.addingTimeInterval(-600))
        let facts = CoachFacts.make(from: [event], goal: .strength, experience: .intermediate, now: now)
        XCTAssertNotNil(facts.recovery.byExercise["Deadlift"])
        let window = facts.recovery.byExercise["Deadlift"]!
        XCTAssertTrue(window.hardEligibleAt > now)
    }

    func testHighFatigueExtendsRecoveryWindow() throws {
        let ctx = try makeContext()
        let now = testNow
        let session = try WorkoutRepository.createSession(date: now.addingTimeInterval(-1200), in: ctx)
        let deadlift = try WorkoutRepository.findOrCreateExercise(
            named: "Deadlift", primaryMuscles: ["hamstrings", "lower-back"], in: ctx)
        for _ in 0..<8 {
            _ = try WorkoutRepository.addSet(to: session, exercise: deadlift, weightKg: 140, reps: 3, rpe: 10, in: ctx)
        }
        session.endedAt = now.addingTimeInterval(-600)

        let event = TrainingEvent.from(session: session)
        let facts = CoachFacts.make(from: [event!], goal: .strength, experience: .intermediate, now: now)
        let window = facts.recovery.byExercise["Deadlift"]
        XCTAssertNotNil(window)
        let hours = window!.hardEligibleAt.timeIntervalSince(window!.lastExposedAt) / 3600
        XCTAssertEqual(hours, 72, accuracy: 1)
    }

    func testPatternCoverageTracksAllTrainedPatterns() throws {
        let ctx = try makeContext()
        let now = testNow
        let squat = try makeStrengthEvent(context: ctx, name: "Back Squat", primaryMuscles: ["quadriceps"],
                                           weight: 100, reps: 5, rpe: 8, date: now.addingTimeInterval(-3600))
        let bench = try makeStrengthEvent(context: ctx, name: "Bench Press", primaryMuscles: ["chest"],
                                           weight: 80, reps: 5, rpe: 8, date: now.addingTimeInterval(-3600))

        let facts = CoachFacts.make(from: [squat, bench], goal: .strength, experience: .intermediate, now: now)
        XCTAssertTrue(facts.weeklyBalance.patternsTrained.contains(.squat))
        XCTAssertTrue(facts.weeklyBalance.patternsTrained.contains(.horizontalPush))
    }

    func testInProgressSetsDontCountAsCompletedDose() throws {
        let ctx = try makeContext()
        let now = testNow
        let completedEvent = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                                    weight: 100, reps: 5, rpe: 8, date: now.addingTimeInterval(-3600))

        let inProgSession = try WorkoutRepository.createSession(date: now.addingTimeInterval(-300), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(
            named: "InProg Bench", primaryMuscles: ["chest"], in: ctx)
        _ = try WorkoutRepository.addSet(to: inProgSession, exercise: bench, weightKg: 80, reps: 5, in: ctx)
        let inProgEvent = TrainingEvent.from(session: inProgSession)!

        let facts = CoachFacts.make(from: [completedEvent, inProgEvent], goal: .strength,
                                     experience: .intermediate, now: now)
        XCTAssertEqual(facts.rolling7dCompletedEvents.count, 1)
        XCTAssertEqual(facts.weeklyBalance.strengthDays, 1)
    }

    func testConsecutiveHardDaysTracking() throws {
        let ctx = try makeContext()
        let now = testNow
        var events: [TrainingEvent] = []
        for daysAgo in 1...3 {
            let date = now.addingTimeInterval(-Double(daysAgo) * 86400)
            let session = try WorkoutRepository.createSession(date: date.addingTimeInterval(-600), in: ctx)
            let squat = try WorkoutRepository.findOrCreateExercise(
                named: "Consec Squat \(daysAgo)", primaryMuscles: ["quadriceps"], in: ctx)
            for _ in 0..<8 {
                _ = try WorkoutRepository.addSet(to: session, exercise: squat, weightKg: 100, reps: 5, rpe: 9, in: ctx)
            }
            session.endedAt = date
            events.append(TrainingEvent.from(session: session)!)
        }

        let facts = CoachFacts.make(from: events, goal: .strength, experience: .intermediate, now: now)
        XCTAssertGreaterThanOrEqual(facts.weeklyBalance.consecutiveHardDays, 3)
    }
}
