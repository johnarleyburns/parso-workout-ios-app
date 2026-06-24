import XCTest
import SwiftData
@testable import CadenceCore

final class CoachDecisionEngineTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private var testNow: Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 5; comps.hour = 12; comps.minute = 0; comps.second = 0
        return cal.date(from: comps) ?? Date()
    }

    private func makeStrengthEvent(context: ModelContext, name: String,
                                    primaryMuscles: [String], date: Date, sets: Int = 3,
                                    rpe: Double? = 8) throws -> TrainingEvent {
        let session = try WorkoutRepository.createSession(date: date.addingTimeInterval(-600), in: context)
        let ex = try WorkoutRepository.findOrCreateExercise(
            named: name, primaryMuscles: primaryMuscles, in: context)
        for _ in 0..<sets {
            _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 100, reps: 5, rpe: rpe, in: context)
        }
        session.endedAt = date
        return TrainingEvent.from(session: session)!
    }

    private func makeCardioEvent(context: ModelContext, type: CardioType, date: Date,
                                  duration: TimeInterval, avgHR: Double?) -> TrainingEvent {
        let cardio = CardioWorkout(type: type, start: date.addingTimeInterval(-duration),
                                    end: date, avgHeartRate: avgHR, source: .iphone)
        context.insert(cardio)
        return TrainingEvent.from(cardio: cardio)
    }

    // MARK: - Balance decisions

    func testTwoStrengthDaysZeroAerobicPrefersAerobic() throws {
        let ctx = try makeContext()
        let now = testNow
        let s1 = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                        date: now.addingTimeInterval(-3 * 86400))
        let s2 = try makeStrengthEvent(context: ctx, name: "Bench", primaryMuscles: ["chest"],
                                        date: now.addingTimeInterval(-6 * 86400))
        let facts = CoachFacts.make(from: [s1, s2], goal: .strength, experience: .intermediate, now: now)

        let decision = CoachDecisionEngine.run(facts)
        XCTAssertTrue(decision.primary.kind == .moderateAerobic || decision.primary.kind == .easyAerobic,
                      "With 2 strength days and 0 aerobic, primary should be aerobic. Got: \(decision.primary.kind)")
    }

    func testZeroStrengthDaysOneFiftyAerobicPrefersStrength() throws {
        let ctx = try makeContext()
        let now = testNow
        let runs: [TrainingEvent] = [
            makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-1 * 86400), duration: 3600, avgHR: 140),
            makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-2 * 86400), duration: 3600, avgHR: 140),
            makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-3 * 86400), duration: 3600, avgHR: 140),
        ]
        let facts = CoachFacts.make(from: runs, goal: .strength, experience: .intermediate, now: now)

        let decision = CoachDecisionEngine.run(facts)
        XCTAssertEqual(decision.primary.kind, .strength,
                       "With 0 strength and aerobic met, primary should be strength. Got: \(decision.primary.kind)")
    }

    // MARK: - Pain concern

    func testPainConcernBlocksHardTraining() throws {
        let ctx = try makeContext()
        let now = testNow
        let events: [TrainingEvent] = []
        let facts = CoachFacts.make(from: events, goal: .strength, experience: .intermediate, now: now)

        let decision = CoachDecisionEngine.run(facts, hasPainConcern: true)
        XCTAssertEqual(decision.primary.kind, .rest)
        XCTAssertFalse(decision.warnings.isEmpty)
    }

    // MARK: - Beginner

    func testBeginnerGetsBeginnerSessions() throws {
        let ctx = try makeContext()
        let now = testNow
        let events: [TrainingEvent] = []
        let facts = CoachFacts.make(from: events, goal: .strength, experience: .beginner, now: now)

        let decision = CoachDecisionEngine.run(facts)
        let candidates = CoachSession.candidates(for: facts)
        XCTAssertTrue(candidates.contains { $0.id == "strength.beginnerA" })
        XCTAssertTrue(candidates.contains { $0.id == "strength.beginnerB" })
    }

    // MARK: - Determinism

    func testDecisionIsDeterministic() throws {
        let ctx = try makeContext()
        let now = testNow
        let s1 = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                        date: now.addingTimeInterval(-3 * 86400))
        let facts = CoachFacts.make(from: [s1], goal: .strength, experience: .intermediate, now: now)

        let d1 = CoachDecisionEngine.run(facts)
        let d2 = CoachDecisionEngine.run(facts)
        XCTAssertEqual(d1.primary.id, d2.primary.id)
    }

    // MARK: - WeeklyPlan generation

    func testWeeklyPlanIncludesSevenDays() throws {
        let ctx = try makeContext()
        let now = testNow
        let events: [TrainingEvent] = []
        let facts = CoachFacts.make(from: events, goal: .strength, experience: .intermediate, now: now)

        let plan = WeeklyPlan.generate(from: facts)
        XCTAssertEqual(plan.days.count, 7)
        XCTAssertTrue(plan.days.contains { $0.isToday })
    }

    func testWeeklyPlanShowsCompletedDays() throws {
        let ctx = try makeContext()
        let now = testNow
        let s1 = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                        date: now.addingTimeInterval(-2 * 86400))
        let facts = CoachFacts.make(from: [s1], goal: .strength, experience: .intermediate, now: now)

        let plan = WeeklyPlan.generate(from: facts)
        let completed = plan.days.filter(\.isCompleted)
        XCTAssertFalse(completed.isEmpty)
    }

    // MARK: - Observed facts (v2 rich model)

    func testObservedFactsIncludeLastCardio() throws {
        let ctx = try makeContext()
        let now = testNow
        let run = makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-3600),
                                  duration: 1800, avgHR: 135)
        let facts = CoachFacts.make(from: [run], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        let cardioFact = decision.observedFacts.first { $0.kind == .lastCardio }
        XCTAssertNotNil(cardioFact, "Should have last cardio fact when cardio exists")
        XCTAssertEqual(cardioFact?.title, "Last cardio")
    }

    func testObservedFactsUseStaticSummaryValues() throws {
        let ctx = try makeContext()
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        for fact in decision.observedFacts {
            if fact.kind == .weeklyStrengthDays || fact.kind == .weeklyModerateEquivalentMinutes {
                XCTAssertNil(fact.occurredAt, "Summary facts should have nil occurredAt, got \(fact.occurredAt?.description ?? "nil")")
            }
        }
    }

    func testObservedFactsPickNewestCardioWhenEventsUnsorted() throws {
        let ctx = try makeContext()
        let now = testNow
        let c1 = makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-7200),
                                 duration: 1800, avgHR: 135)
        let c2 = makeCardioEvent(context: ctx, type: .walk, date: now.addingTimeInterval(-3600),
                                  duration: 2400, avgHR: 110)
        let facts = CoachFacts.make(from: [c1, c2], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        let cardioFact = decision.observedFacts.first { $0.kind == .lastCardio }
        XCTAssertNotNil(cardioFact)
        XCTAssertTrue(cardioFact!.detail?.contains("Walk") ?? false,
                      "Should pick the most recent (walk), got: \(cardioFact?.detail ?? "nil")")
    }

    func testNoEvidenceDuplicationDataNeededForInlineSources() throws {
        let ctx = try makeContext()
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        // The engine always produces inline citations (on claim, warnings, rule-out).
        // We just check the decision is well-formed.
        XCTAssertFalse(decision.primary.id.isEmpty)
    }

    // MARK: - Expanded alternatives

    func testModerateAerobicAlternativesIncludeRunWalkCycleSwimOrRow() throws {
        let ctx = try makeContext()
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let candidates = CoachSession.candidates(for: facts)
        let moderateIDs = candidates.filter { $0.kind == .moderateAerobic }.map(\.id)
        XCTAssertTrue(moderateIDs.contains("aerobic.moderateRun"))
        XCTAssertTrue(moderateIDs.contains("aerobic.moderateWalk"))
        XCTAssertTrue(moderateIDs.contains("aerobic.moderateCycle"))
        XCTAssertTrue(moderateIDs.contains("aerobic.moderateSwim"))
        XCTAssertTrue(moderateIDs.contains("aerobic.moderateRow"))
    }

    // MARK: - Preference-aware scoring

    func testPreferenceForCyclingReordersEligibleModerateAerobicCandidates() throws {
        let ctx = try makeContext()
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)

        var profile = CoachPreferenceProfile.empty
        profile.aerobicPreferences = [
            AerobicPreference(intent: .moderateAerobic, modality: .cycle, score: 5, updatedAt: now)
        ]

        let decision = CoachDecisionEngine.run(facts, profile: profile)
        // With strong cycle preference, cycle should be primary for moderate aerobic
        XCTAssertEqual(decision.primary.kind, .moderateAerobic)
        XCTAssertEqual(decision.primary.modality, .cycle,
                       "With cycle preference, primary should be cycle. Got: \(decision.primary.modality?.rawValue ?? "nil")")
    }

    func testPreferenceDoesNotOverrideRecoveryEligibility() throws {
        let ctx = try makeContext()
        let now = testNow
        // Recent hard lower-body squat (within recovery window)
        let squat = try makeStrengthEvent(context: ctx, name: "Back Squat",
                                          primaryMuscles: ["quadriceps", "glutes"],
                                          date: now.addingTimeInterval(-6 * 3600),
                                          sets: 5, rpe: 9)
        let facts = CoachFacts.make(from: [squat], goal: .strength, experience: .intermediate, now: now)

        var profile = CoachPreferenceProfile.empty
        profile.aerobicPreferences = [
            AerobicPreference(intent: .moderateAerobic, modality: .run, score: 10, updatedAt: now)
        ]

        let decision = CoachDecisionEngine.run(facts, profile: profile)
        // Run should be deferred (not primary) due to lower-body collision
        let deferredRun = decision.deferred.first { $0.session.id == "aerobic.moderateRun" }
        XCTAssertNotNil(deferredRun, "Run should be deferred due to recovery, despite preference")
    }

    func testHighImpactAvoidanceKeepsRunOutOfPrimaryWhenLowImpactCanFulfillIntent() throws {
        let ctx = try makeContext()
        let now = testNow

        var profile = CoachPreferenceProfile.empty
        profile.avoidedTags = ["highImpact"]

        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts, profile: profile)
        // With highImpact avoided, primary should not be run
        if decision.primary.kind == .moderateAerobic {
            XCTAssertNotEqual(decision.primary.modality, .run,
                              "Run should not be primary when highImpact is avoided")
        }
    }
}
