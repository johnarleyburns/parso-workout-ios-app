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

    /// Home supplies events newest-first (cardio block descending). The engine must
    /// pick the most recent cardio by end date, not the first in the array.
    func testObservedFactsPickNewestCardioWhenEventsAreNewestFirst() throws {
        let ctx = try makeContext()
        let now = testNow
        let newWalk = makeCardioEvent(context: ctx, type: .walk, date: now.addingTimeInterval(-3600),
                                      duration: 2400, avgHR: 110)
        let oldRun = makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-2 * 86400),
                                     duration: 1800, avgHR: 150)
        let facts = CoachFacts.make(from: [newWalk, oldRun], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        let cardioFact = decision.observedFacts.first { $0.kind == .lastCardio }
        XCTAssertNotNil(cardioFact)
        XCTAssertTrue(cardioFact!.detail?.contains("Walk") ?? false,
                      "Should pick the most recent cardio (walk), got: \(cardioFact?.detail ?? "nil")")
    }

    /// Home supplies strength events newest-first. Pick newest strength by end date.
    func testObservedFactsPickNewestStrengthWhenHomeSuppliesNewestFirst() throws {
        let ctx = try makeContext()
        let now = testNow
        let newBench = try makeStrengthEvent(context: ctx, name: "Bench Press", primaryMuscles: ["chest"],
                                             date: now.addingTimeInterval(-1 * 86400))
        let oldSquat = try makeStrengthEvent(context: ctx, name: "Back Squat", primaryMuscles: ["quadriceps"],
                                             date: now.addingTimeInterval(-2 * 86400))
        let facts = CoachFacts.make(from: [newBench, oldSquat], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        let strengthFact = decision.observedFacts.first { $0.kind == .lastStrength }
        XCTAssertNotNil(strengthFact)
        XCTAssertTrue(strengthFact!.detail?.contains("Bench") ?? false,
                      "Should pick the most recent strength (bench), got: \(strengthFact?.detail ?? "nil")")
    }

    /// Home-like ordering: all strength newest-to-oldest, then all cardio
    /// newest-to-oldest. The engine must pick the newest of each by end date.
    func testObservedFactsPickNewestForHomeMixedOrdering() throws {
        let ctx = try makeContext()
        let now = testNow
        let newBench = try makeStrengthEvent(context: ctx, name: "Bench Press", primaryMuscles: ["chest"],
                                             date: now.addingTimeInterval(-1 * 86400))
        let oldSquat = try makeStrengthEvent(context: ctx, name: "Back Squat", primaryMuscles: ["quadriceps"],
                                             date: now.addingTimeInterval(-2 * 86400))
        let newWalk = makeCardioEvent(context: ctx, type: .walk, date: now.addingTimeInterval(-3600),
                                      duration: 2400, avgHR: 110)
        let oldRun = makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-2 * 86400),
                                     duration: 1800, avgHR: 150)
        // Strength block (newest→oldest) then cardio block (newest→oldest).
        let facts = CoachFacts.make(from: [newBench, oldSquat, newWalk, oldRun],
                                    goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        let strengthFact = decision.observedFacts.first { $0.kind == .lastStrength }
        let cardioFact = decision.observedFacts.first { $0.kind == .lastCardio }
        XCTAssertTrue(strengthFact?.detail?.contains("Bench") ?? false,
                      "newest strength should be bench, got: \(strengthFact?.detail ?? "nil")")
        XCTAssertTrue(cardioFact?.detail?.contains("Walk") ?? false,
                      "newest cardio should be walk, got: \(cardioFact?.detail ?? "nil")")
    }

    /// A future-dated event (e.g. clock skew / scheduled import) must never be
    /// treated as the last event or counted in the weekly balance.
    func testFutureEventsDoNotCountAsLastOrWeeklyBalance() throws {
        let ctx = try makeContext()
        let now = testNow
        let pastWalk = makeCardioEvent(context: ctx, type: .walk, date: now.addingTimeInterval(-3600),
                                       duration: 1800, avgHR: nil)   // moderate ⇒ 30 mod-eq min
        let futureRun = makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(86400),
                                        duration: 3600, avgHR: 160)  // vigorous ⇒ 120 mod-eq if wrongly counted
        let facts = CoachFacts.make(from: [futureRun, pastWalk], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        let cardioFact = decision.observedFacts.first { $0.kind == .lastCardio }
        XCTAssertTrue(cardioFact?.detail?.contains("Walk") ?? false,
                      "last cardio should be the past walk, not the future run; got: \(cardioFact?.detail ?? "nil")")
        let modEquiv = facts.weeklyBalance.moderateEquivalentMinutes
        XCTAssertGreaterThan(modEquiv, 0, "past walk should count")
        XCTAssertLessThanOrEqual(modEquiv, 35,
                                 "future run must be excluded from weekly balance; got \(modEquiv) min")
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

    // MARK: - Cardio-type fidelity (preferences remember the actual modality)

    /// Aerobic floor behind, strength floor met, no lower-body collision — so any
    /// moderate-aerobic modality is eligible and can win on preference.
    private func aerobicGapFacts(_ ctx: ModelContext, _ now: Date) throws -> CoachFacts {
        let s1 = try makeStrengthEvent(context: ctx, name: "Bench Press", primaryMuscles: ["chest"],
                                       date: now.addingTimeInterval(-2 * 86400))
        let s2 = try makeStrengthEvent(context: ctx, name: "Barbell Row", primaryMuscles: ["back"],
                                       date: now.addingTimeInterval(-3 * 86400))
        return CoachFacts.make(from: [s1, s2], goal: .strength, experience: .intermediate, now: now)
    }

    /// Boxing must carry its OWN modality (not `.other`), so selecting it records a
    /// boxing preference and Coach recommends boxing next.
    func testSelectingBoxingRemembersBoxingModalityNotOther() throws {
        let ctx = try makeContext()
        let now = testNow
        let facts = try aerobicGapFacts(ctx, now)
        let candidates = CoachSession.candidates(for: facts)
        let boxing = candidates.first { $0.id == "aerobic.moderateBoxing" }
        XCTAssertEqual(boxing?.modality, .boxing, "boxing candidate must carry its true modality")

        var profile = CoachPreferenceProfile.empty
        profile.recordSelection(boxing!, from: candidates)
        XCTAssertEqual(profile.aerobicPreferences.first?.modality, .boxing,
                       "selecting boxing must store a boxing preference, never .other")

        let decision = CoachDecisionEngine.run(facts, profile: profile)
        XCTAssertEqual(decision.primary.modality, .boxing,
                       "with a remembered boxing preference, Coach should recommend boxing")
    }

    /// Picking a modality that isn't the default winner (swim) must be remembered
    /// and recommended next — proving cardio-type fidelity for any modality.
    func testSelectingSwimRemembersAndRecommendsSwim() throws {
        let ctx = try makeContext()
        let now = testNow
        let facts = try aerobicGapFacts(ctx, now)
        let candidates = CoachSession.candidates(for: facts)
        let swim = candidates.first { $0.id == "aerobic.moderateSwim" }!

        // Default (no preference) Coach does not pick swim.
        XCTAssertNotEqual(CoachDecisionEngine.run(facts).primary.modality, .swim)

        var profile = CoachPreferenceProfile.empty
        profile.recordSelection(swim, from: candidates)
        XCTAssertEqual(profile.aerobicPreferences.first?.modality, .swim)

        XCTAssertEqual(CoachDecisionEngine.run(facts, profile: profile).primary.modality, .swim,
                       "Coach must remember the swim preference and recommend it next")
    }

    /// The stored preference survives a Codable round-trip (UserDefaults storage),
    /// so boxing fidelity isn't lost on relaunch.
    func testBoxingPreferenceSurvivesCodableRoundTrip() throws {
        var profile = CoachPreferenceProfile.empty
        profile.aerobicPreferences = [
            AerobicPreference(intent: .moderateAerobic, modality: .boxing, score: 2, updatedAt: Date())
        ]
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(CoachPreferenceProfile.self, from: data)
        XCTAssertEqual(decoded.aerobicPreferences.first?.modality, .boxing)
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
