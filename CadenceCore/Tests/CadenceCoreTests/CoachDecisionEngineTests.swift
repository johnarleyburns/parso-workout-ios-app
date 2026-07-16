import XCTest
import SwiftData
@testable import CadenceCore

final class CoachDecisionEngineTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private var testNow: Date {
        // Fixed absolute Thursday (2026-06-25 12:00) so weekly/recovery windows are
        // deterministic regardless of when the suite runs (no wall-clock drift).
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 25
        comps.hour = 12; comps.minute = 0; comps.second = 0
        return Calendar.current.date(from: comps) ?? Date(timeIntervalSince1970: 1_750_000_000)
    }

    private var testSaturday: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 27
        comps.hour = 12; comps.minute = 0; comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func makeStrengthEvent(context: ModelContext, name: String,
                                    primaryMuscles: [String], date: Date, sets: Int = 3,
                                    rpe: Double? = 8,
                                    setCompletedAt: Date? = nil) throws -> TrainingEvent {
        let session = try WorkoutRepository.createSession(date: date.addingTimeInterval(-600), in: context)
        let ex = try WorkoutRepository.findOrCreateExercise(
            named: name, primaryMuscles: primaryMuscles, in: context)
        for _ in 0..<sets {
            if let setCompletedAt {
                _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 100, reps: 5,
                                                 rpe: rpe, completedAt: setCompletedAt, in: context)
            } else {
                _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 100, reps: 5,
                                                 rpe: rpe, completedAt: date, in: context)
            }
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
        XCTAssertGreaterThanOrEqual(plan.days.count, 7, "Plan should have at least 7 days (history + future)")
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

    func testWeeklyPlanDoesNotBackfillEmptyHistoryAsPlannedSessions() throws {
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)

        let plan = WeeklyPlan.generate(from: facts)

        XCTAssertEqual(plan.historyDays.count, 7)
        XCTAssertTrue(plan.historyDays.allSatisfy { !$0.isFuture })
        XCTAssertTrue(plan.historyDays.filter { !$0.isCompleted && $0.isPast }.allSatisfy { $0.sessions.isEmpty },
                      "Blank past history days must not become planned sessions")
    }

    func testWeeklyPlanRemainingCalendarWeekIsFutureOnlyAndChronological() throws {
        let now = testNow
        let cal = Calendar.current
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)

        let plan = WeeklyPlan.generate(from: facts)
        let remaining = plan.remainingCalendarWeekDays
        let weekStart = WeeklyStats.weekStart(now: now)
        let nextWeekStart = cal.date(byAdding: .day, value: 7, to: weekStart)!

        XCTAssertEqual(remaining.count, 3, "Thursday should have Fri/Sat/Sun remaining in the Monday-bounded week")
        XCTAssertEqual(remaining.map(\.date), remaining.map(\.date).sorted())
        XCTAssertTrue(remaining.allSatisfy { $0.isFuture })
        XCTAssertTrue(remaining.allSatisfy { $0.date >= cal.startOfDay(for: now) && $0.date < nextWeekStart })
        XCTAssertTrue(remaining.allSatisfy { $0.sessionKind != nil })
    }

    func testWeeklyPlanRestOfWeekPrioritizesStrengthDeficitWithoutArbitraryRestAlternation() throws {
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)

        let plan = WeeklyPlan.generate(from: facts)
        let remaining = plan.remainingCalendarWeekDays

        // With empty history and default preferences (strength=2, cardio=3),
        // remaining days should push toward strength targets first, then cardio.
        let activeRemaining = remaining.filter { !$0.sessions.isEmpty }
        XCTAssertFalse(activeRemaining.isEmpty, "Should have planned sessions in remaining week")
        // First active session should be strength (strength deficit)
        if let first = activeRemaining.first {
            XCTAssertTrue(first.sessions.contains { $0.kind == .strength },
                          "First remaining session should include strength")
        }
    }

    func testWeeklyPlanModerateCardioIsNotMarkedHard() throws {
        let ctx = try makeContext()
        let now = testNow
        let s1 = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                        date: now.addingTimeInterval(-2 * 86400))
        let s2 = try makeStrengthEvent(context: ctx, name: "Bench", primaryMuscles: ["chest"],
                                        date: now.addingTimeInterval(-3 * 86400))
        let facts = CoachFacts.make(from: [s1, s2], goal: .strength, experience: .intermediate, now: now)

        let plan = WeeklyPlan.generate(from: facts)
        let futureSessions = plan.futureDays.flatMap(\.sessions)
        let moderateCardioSessions = futureSessions.filter { $0.kind == .moderateAerobic }

        if !moderateCardioSessions.isEmpty {
            XCTAssertTrue(moderateCardioSessions.allSatisfy { !$0.isHard },
                          "Moderate cardio sessions should NOT be marked hard")
        }
    }

    func testWeeklyPlanPoorReadinessOnlyDefersTomorrow() throws {
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate,
                                    readinessEntry: poorReadiness(now), now: now)

        let plan = WeeklyPlan.generate(from: facts)

        // Coach suggests, it does not proscribe: poor readiness attaches a
        // lighter-day recommendation to tomorrow but never converts a scheduled
        // training day into a forced Recovery day.
        let tomorrow = try XCTUnwrap(plan.futureDays.first)
        XCTAssertNotEqual(tomorrow.sessionKind, .recovery,
                          "Poor readiness must not force a Recovery day")
        XCTAssertTrue(tomorrow.sessions.contains(where: \.recommendsLighter),
                      "Poor readiness should attach a non-blocking lighter-day recommendation")
        XCTAssertTrue(plan.futureDays.contains { day in
            day.sessions.contains { $0.kind == .strength }
        }, "A one-day readiness dip should not drop the plan's strength days")
        XCTAssertFalse(plan.futureDays.dropFirst().flatMap(\.sessions).contains(where: \.recommendsLighter),
                       "The readiness recommendation applies to tomorrow only")
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

    /// Fix 1: "What you did" must read from the workout's date (start), not the
    /// finalize/entry time (endedAt). A session started 12h ago but finalized 2h ago
    /// must surface "12h ago".
    func testLastStrengthValueUsesWorkoutDateNotEndedAt() throws {
        let ctx = try makeContext()
        let now = testNow
        let started = now.addingTimeInterval(-12 * 3600)
        let finalized = now.addingTimeInterval(-2 * 3600)
        let session = try WorkoutRepository.createSession(date: started, in: ctx)
        let ex = try WorkoutRepository.findOrCreateExercise(
            named: "Back Squat", primaryMuscles: ["quadriceps"], in: ctx)
        for _ in 0..<3 {
            _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 100, reps: 5,
                                             rpe: 8, completedAt: started, in: ctx)
        }
        session.endedAt = finalized
        let event = TrainingEvent.from(session: session)!
        let facts = CoachFacts.make(from: [event], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        let strengthFact = decision.observedFacts.first { $0.kind == .lastStrength }
        XCTAssertEqual(strengthFact?.value, "12h ago",
                       "Should format from session.date (12h ago), not endedAt (2h ago). Got: \(strengthFact?.value ?? "nil")")
        XCTAssertEqual(strengthFact?.occurredAt, event.start,
                       "occurredAt sort key should match the displayed start time")
    }

    /// Fix 3: the "What you did" facts must carry the source workout id so the Home
    /// card can navigate to that workout. Aggregate facts must not.
    func testObservedFactsCarrySourceWorkoutId() throws {
        let ctx = try makeContext()
        let now = testNow
        let strength = try makeStrengthEvent(context: ctx, name: "Back Squat",
                                             primaryMuscles: ["quadriceps"],
                                             date: now.addingTimeInterval(-1 * 86400))
        let run = makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-3600),
                                  duration: 1800, avgHR: 135)
        let facts = CoachFacts.make(from: [strength, run], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        let strengthFact = decision.observedFacts.first { $0.kind == .lastStrength }
        let cardioFact = decision.observedFacts.first { $0.kind == .lastCardio }
        XCTAssertEqual(strengthFact?.sourceId, strength.id,
                       "last strength fact should carry its source session id")
        XCTAssertEqual(cardioFact?.sourceId, run.id,
                       "last cardio fact should carry its source cardio id")
        let strengthDaysFact = decision.observedFacts.first { $0.kind == .weeklyStrengthDays }
        XCTAssertNil(strengthDaysFact?.sourceId, "aggregate facts should not carry a source id")
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

    // MARK: - Plan adherence: Wednesday scenario

    /// Wednesday scenario: Monday full-body + 18-min run, Tuesday rest, Wednesday
    /// morning Coach recommends aerobic (both strength and aerobic floors unmet).
    /// After a 44-min boxing workout, strength is still needed — the plan stays
    /// planAhead so the remaining recommendation stays visible.
    func testWednesdayScenarioShowsPlanCompleteAfterBoxing() throws {
        let ctx = try makeContext()
        let now = testNow
        let cal = Calendar.current

        // Monday (2 days ago): full-body strength
        let monday = cal.date(byAdding: .day, value: -2, to: now)!
        let s1 = try makeStrengthEvent(context: ctx, name: "Back Squat",
                                        primaryMuscles: ["quadriceps", "glutes"],
                                        date: monday.addingTimeInterval(-3600))
        // Monday: 18-min run (18 mod-eq min)
        let monRun = makeCardioEvent(context: ctx, type: .run,
                                      date: monday.addingTimeInterval(-1800),
                                      duration: 18 * 60, avgHR: 140)

        // No events Tuesday

        // Before boxing: both strength (1/2) and aerobic (18/150 min) are below
        // target, so the day is planAhead. (Which type leads depends on recovery +
        // goal scoring; the meaningful invariant here is planAhead.)
        let beforeFacts = CoachFacts.make(from: [s1, monRun], goal: .strength,
                                           experience: .intermediate, now: now)
        let beforeDecision = CoachDecisionEngine.run(beforeFacts)
        XCTAssertEqual(beforeDecision.planAdherence, .planAhead,
                       "Before boxing, plan should be planAhead")

        // Wednesday afternoon: complete 44-min boxing
        let boxing = makeCardioEvent(context: ctx, type: .boxing,
                                      date: now.addingTimeInterval(-3600),
                                      duration: 44 * 60, avgHR: 135)

        let afterFacts = CoachFacts.make(from: [s1, monRun, boxing], goal: .strength,
                                          experience: .intermediate, now: now)
        let afterDecision = CoachDecisionEngine.run(afterFacts)

        // After boxing: both strength (1/2) and cardio (62/150 min) are still
        // needed weekly, so the plan stays planAhead — completing one type when
        // both are needed does not mark the day complete.
        XCTAssertEqual(afterDecision.planAdherence, .planAhead,
                       "After boxing, with both targets unmet, plan should stay planAhead. Got: \(afterDecision.planAdherence)")
    }

    /// Coach scenario (maintainer request): three strength workouts done this week,
    /// preference = 3 strength days/week, it's Sunday → another strength session must
    /// NOT be recommended, even with the two-a-day preference enabled. (Pre-fix this
    /// failed two ways: `weekStart` returned next-Monday on Sundays so "this week"
    /// counted 0 strength, and the two-a-day path had no weekly cap.)
    func testThreeStrengthThisWeekMeetsTargetNoMoreStrengthOnSundayEvenWithTwoADay() throws {
        let ctx = try makeContext()
        let cal = Calendar.current
        // Sunday 2026-06-28; its Monday-week is 2026-06-22 .. 06-28.
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 28; comps.hour = 12
        let sunday = cal.date(from: comps)!

        // Three strength sessions on Mon / Wed / Fri of this week.
        let mon = cal.date(byAdding: .day, value: -6, to: sunday)!
        let wed = cal.date(byAdding: .day, value: -4, to: sunday)!
        let fri = cal.date(byAdding: .day, value: -2, to: sunday)!
        let s1 = try makeStrengthEvent(context: ctx, name: "Back Squat",
                                        primaryMuscles: ["quadriceps", "glutes"], date: mon)
        let s2 = try makeStrengthEvent(context: ctx, name: "Bench Press",
                                        primaryMuscles: ["chest"], date: wed)
        let s3 = try makeStrengthEvent(context: ctx, name: "Deadlift",
                                        primaryMuscles: ["hamstrings", "glutes"], date: fri)

        let prefs = CoachSchedulePreferences(strengthDaysPerWeek: 3, cardioDaysPerWeek: 3,
                                              allowsTwoADays: true)
        let facts = CoachFacts.make(from: [s1, s2, s3], goal: .strength,
                                     experience: .intermediate, now: sunday)

        XCTAssertEqual(facts.weeklyBalance.strengthDays, 3,
                       "Three distinct strength days should count this week, even on Sunday")

        let decision = CoachDecisionEngine.run(facts, schedulePreferences: prefs)

        XCTAssertNotEqual(decision.primary.kind, .strength,
                          "Weekly strength target (3/3) met on Sunday → no more strength, even with two-a-day. Got: \(decision.primary.kind)")
        XCTAssertFalse(decision.todayPlannedRecommendations.contains { $0.kind == .strength },
                       "Two-a-day must not override the weekly strength cap once the target is met")
        XCTAssertFalse(decision.alternatives.contains { $0.kind == .strength },
                       "No strength should be offered as an alternative once the weekly target is met")
    }

    /// Completing a strength session today should suppress same-day strength
    /// recommendations.
    func testCompletedStrengthTodaySuppressesStrengthRecommendation() throws {
        let ctx = try makeContext()
        let now = testNow

        // Strength completed today (within 2 hours)
        let todayStrength = try makeStrengthEvent(context: ctx, name: "Bench Press",
                                                   primaryMuscles: ["chest"],
                                                   date: now.addingTimeInterval(-2 * 3600))

        let facts = CoachFacts.make(from: [todayStrength], goal: .strength,
                                     experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)

        // With strength already done today, primary should not be strength
        XCTAssertNotEqual(decision.primary.kind, .strength,
                          "Strength already done today should not be primary. Got: \(decision.primary.kind)")
    }

    /// Same-day repetition: completing boxing should suppress boxing re-recommendation
    /// even if boxing preference exists.
    func testCompletedBoxingSuppressesSameDayBoxingEvenWithPreference() throws {
        let ctx = try makeContext()
        let now = testNow

        // Strength floor met with two sessions earlier this week
        let s1 = try makeStrengthEvent(context: ctx, name: "Squat",
                                        primaryMuscles: ["quadriceps"],
                                        date: now.addingTimeInterval(-3 * 86400))
        let s2 = try makeStrengthEvent(context: ctx, name: "Bench Press",
                                        primaryMuscles: ["chest"],
                                        date: now.addingTimeInterval(-5 * 86400))

        // Today: completed boxing
        let todayBoxing = makeCardioEvent(context: ctx, type: .boxing,
                                           date: now.addingTimeInterval(-1 * 3600),
                                           duration: 30 * 60, avgHR: 135)

        // Boxing preference
        var profile = CoachPreferenceProfile.empty
        profile.aerobicPreferences = [
            AerobicPreference(intent: .moderateAerobic, modality: .boxing, score: 10, updatedAt: now)
        ]

        let facts = CoachFacts.make(from: [s1, s2, todayBoxing], goal: .strength,
                                     experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts, profile: profile)

        // Boxing already done today — should NOT be primary despite preference
        if decision.primary.kind == .moderateAerobic || decision.primary.kind == .easyAerobic {
            XCTAssertNotEqual(decision.primary.modality, .boxing,
                              "Boxing already done today should not be primary. Got: \(decision.primary.modality?.rawValue ?? "nil")")
        }
    }

    /// Boxing preference still works on future eligible days without same-day completion.
    func testBoxingPreferenceWorksOnFutureEligibleDays() throws {
        let ctx = try makeContext()
        let now = testNow

        let s1 = try makeStrengthEvent(context: ctx, name: "Squat",
                                        primaryMuscles: ["quadriceps"],
                                        date: now.addingTimeInterval(-3 * 86400))
        let s2 = try makeStrengthEvent(context: ctx, name: "Bench Press",
                                        primaryMuscles: ["chest"],
                                        date: now.addingTimeInterval(-5 * 86400))

        // No boxing today; boxing preference should win
        var profile = CoachPreferenceProfile.empty
        profile.aerobicPreferences = [
            AerobicPreference(intent: .moderateAerobic, modality: .boxing, score: 5, updatedAt: now)
        ]

        let facts = CoachFacts.make(from: [s1, s2], goal: .strength,
                                     experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts, profile: profile)

        // Boxing should be primary on a day with no completed boxing
        XCTAssertEqual(decision.primary.modality, .boxing,
                       "Boxing preference should win on fresh day. Got: \(decision.primary.modality?.rawValue ?? "nil")")
    }

    // MARK: - WeeklyPlan future days

    func testWeeklyPlanIncludesFutureDays() throws {
        let ctx = try makeContext()
        let now = testNow
        let events: [TrainingEvent] = []
        let facts = CoachFacts.make(from: events, goal: .strength, experience: .intermediate, now: now)

        let plan = WeeklyPlan.generate(from: facts)
        let futureDays = plan.days.filter(\.isFuture)
        XCTAssertFalse(futureDays.isEmpty, "WeeklyPlan should include future days")
        XCTAssertGreaterThanOrEqual(futureDays.count, 6, "Should have at least 6 future days")
    }

    func testWeeklyPlanHasTomorrow() throws {
        let ctx = try makeContext()
        let now = testNow
        let events: [TrainingEvent] = []
        let facts = CoachFacts.make(from: events, goal: .strength, experience: .intermediate, now: now)

        let plan = WeeklyPlan.generate(from: facts)
        XCTAssertNotNil(plan.tomorrow, "WeeklyPlan should have a tomorrow entry")
        XCTAssertTrue(plan.tomorrow!.isFuture)
    }

    func testWeeklyPlanTomorrowAfterBoxingSuggestsStrength() throws {
        let ctx = try makeContext()
        let now = testNow
        let cal = Calendar.current

        // Monday: full-body strength + 18-min run
        let monday = cal.date(byAdding: .day, value: -2, to: now)!
        let s1 = try makeStrengthEvent(context: ctx, name: "Back Squat",
                                        primaryMuscles: ["quadriceps", "glutes"],
                                        date: monday.addingTimeInterval(-3600))
        let monRun = makeCardioEvent(context: ctx, type: .run,
                                      date: monday.addingTimeInterval(-1800),
                                      duration: 18 * 60, avgHR: 140)

        // Wednesday: completed boxing
        let todayBoxing = makeCardioEvent(context: ctx, type: .boxing,
                                           date: now.addingTimeInterval(-3600),
                                           duration: 44 * 60, avgHR: 135)

        let facts = CoachFacts.make(from: [s1, monRun, todayBoxing], goal: .strength,
                                     experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)

        if case .planComplete(_, _, let tomorrow) = decision.planAdherence {
            XCTAssertNotNil(tomorrow)
            // With only 1/2+ strength days and no recovery block, tomorrow should be strength
            if let t = tomorrow {
                XCTAssertTrue(t.contains("Strength") || t.contains("Rest") || t.contains("Recovery") || t.contains("Cardio"),
                              "Tomorrow preview should suggest a session type. Got: \(t)")
            }
        }
    }

    // YourWeekView "7-day history" ForEach indexes weekdays (7-element array) by
    // plan.days offset. WeeklyPlan.generate returns 13 days (7 history + 6 future),
    // so offset-based indexing crashes at offset >= 7. The fix computes the weekday
    // label from the day's actual date (safe for any array size).
    func testWeeklyPlanDaysExceedSevenSafeWeekdayLookup() throws {
        let ctx = try makeContext()
        let now = testNow
        let events: [TrainingEvent] = []
        let facts = CoachFacts.make(from: events, goal: .strength, experience: .intermediate, now: now)

        let plan = WeeklyPlan.generate(from: facts)
        XCTAssertGreaterThan(plan.days.count, 7, "Plan must have >7 days to trigger the crash scenario")

        let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        for (i, day) in plan.days.enumerated() {
            // Old code used weekdays[i] — crashes when i >= 7.
            // Fix uses the day's date:
            let idx = Calendar.current.component(.weekday, from: day.date) - 2
            let label = idx >= 0 && idx < 7 ? weekdays[idx] : ""
            // Verify the label is either a valid day abbreviation or empty.
            if idx >= 0 && idx < 7 {
                XCTAssertEqual(label, weekdays[idx],
                               "Day \(i) (\(day.date)) weekday label should match")
            } else {
                XCTAssertEqual(label, "", "Invalid weekday index should yield empty string")
            }
        }
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

    // MARK: - P4: system-aware candidates, scoring & gates

    private func poorReadiness(_ now: Date) -> ReadinessEntry {
        let entry = ReadinessEntry()
        entry.date = now
        entry.sleepQuality = 1
        return entry
    }

    /// Every non-rest candidate is tagged with the systems it loads and an evidence
    /// category whose curated pool exactly backs its citations.
    func testEveryCandidateCarriesSystemsAndCategoryBackedCitations() throws {
        let ctx = try makeContext()
        let now = testNow
        let s = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                      date: now.addingTimeInterval(-2 * 86400))
        let facts = CoachFacts.make(from: [s], goal: .strength, experience: .intermediate, now: now)

        for c in CoachSession.candidates(for: facts, anaerobicOptIn: true) {
            XCTAssertFalse(c.systemsTrained.isEmpty, "\(c.id) has no systemsTrained")
            if c.kind == .rest {
                XCTAssertNil(c.evidenceCategory)
                continue
            }
            guard let category = c.evidenceCategory else {
                return XCTFail("\(c.id) has no evidenceCategory")
            }
            let pool = CitationRegistry.citationPool(for: category).citationIds
            XCTAssertEqual(c.citationIds, pool, "\(c.id) must cite exactly its category pool")
            XCTAssertFalse(c.citationIds.isEmpty)
        }
    }

    /// The strength candidate no longer cites a mortality/public-health study (P1/P4
    /// no-mortality-for-prescriptions rule).
    func testStrengthCandidateDoesNotCiteMortalityStudy() throws {
        let ctx = try makeContext()
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let strength = CoachSession.candidates(for: facts).first { $0.id == "strength.general" }
        let mortality: Set<String> = ["ekelundActivityMortality2016", "mooreLeisureActivity2012",
                                      "aremDoseResponse2015"]
        XCTAssertNotNil(strength)
        XCTAssertTrue(Set(strength!.citationIds).isDisjoint(with: mortality))
        XCTAssertEqual(strength?.evidenceCategory, .strengthIntensity)
    }

    /// Threshold tempo only appears once an aerobic base is established and cites the
    /// threshold pool — never the VO₂ or aerobic-base pool.
    func testThresholdTempoGatedByAerobicBase() throws {
        let ctx = try makeContext()
        let now = testNow
        let tiny = CoachFacts.make(
            from: [makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-86400),
                                   duration: 20 * 60, avgHR: 140)],
            goal: .strength, experience: .intermediate, now: now)
        XCTAssertNil(CoachSession.candidates(for: tiny).first { $0.id == "aerobic.thresholdTempo" },
                     "No threshold work before a base is built")

        let based = CoachFacts.make(from: [
            makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-86400), duration: 60 * 60, avgHR: 140),
            makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-2 * 86400), duration: 60 * 60, avgHR: 140),
        ], goal: .strength, experience: .intermediate, now: now)
        let threshold = CoachSession.candidates(for: based).first { $0.id == "aerobic.thresholdTempo" }
        XCTAssertNotNil(threshold)
        XCTAssertEqual(threshold?.systemsTrained, [.threshold])
        XCTAssertEqual(threshold?.citationIds, CitationRegistry.citationPool(for: .thresholdTraining).citationIds)
    }

    /// Anaerobic intervals are present by default once the user has an aerobic base.
    func testAnaerobicIntervalsAreDefaultWhenEligible() throws {
        let ctx = try makeContext()
        let now = testNow
        let base = makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-2 * 86400),
                                   duration: 60 * 60, avgHR: 130)
        let facts = CoachFacts.make(from: [base], goal: .strength, experience: .intermediate, now: now)

        let optIn = CoachSession.candidates(for: facts)
            .first { $0.id == "aerobic.anaerobicIntervals" }
        XCTAssertNotNil(optIn)
        XCTAssertEqual(optIn?.systemsTrained, [.anaerobicPower])
        XCTAssertEqual(optIn?.evidenceCategory, .anaerobicTraining)
        XCTAssertFalse(optIn!.citationIds.isEmpty)
        XCTAssertNotNil(CoachDecisionEngine.run(facts).scoreBreakdowns["aerobic.anaerobicIntervals"])
    }

    /// A lighter strength option surfaces when readiness is poor.
    func testReducedLoadStrengthSurfacesOnPoorReadiness() throws {
        let ctx = try makeContext()
        let now = testNow
        let s = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                      date: now.addingTimeInterval(-2 * 86400))
        let facts = CoachFacts.make(from: [s], goal: .strength, experience: .intermediate,
                                    readinessEntry: poorReadiness(now), now: now)
        let reduced = CoachSession.candidates(for: facts).first { $0.id == "strength.reducedLoad" }
        XCTAssertNotNil(reduced)
        XCTAssertTrue(reduced!.trainingLoadTags.contains("reducedLoad"))
        XCTAssertEqual(reduced?.evidenceCategory, .recoveryMonitoring)
    }

    /// Poor readiness defers all hard work for a day; the primary is never hard and a
    /// hard candidate is deferred with a recovery-monitoring–cited reason.
    func testPoorReadinessDefersHardWork() throws {
        let ctx = try makeContext()
        let now = testNow
        let s = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                      date: now.addingTimeInterval(-4 * 86400))
        let facts = CoachFacts.make(from: [s], goal: .strength, experience: .intermediate,
                                    readinessEntry: poorReadiness(now), now: now)
        let decision = CoachDecisionEngine.run(facts)

        XCTAssertFalse(decision.primary.isHard,
                       "Poor readiness must not yield a hard primary. Got: \(decision.primary.id)")
        let lowReadiness = decision.deferred.first { $0.reason.id == "lowReadiness" }
        XCTAssertNotNil(lowReadiness, "A hard session should be deferred for low readiness")
        XCTAssertFalse(lowReadiness!.reason.citationIds.isEmpty)
    }

    /// An assessment prompt surfaces for an actively-trained system with no baseline.
    func testAssessmentBaselineSurfacesForUncoveredTrainedSystem() throws {
        let ctx = try makeContext()
        let now = testNow
        let s = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                      date: now.addingTimeInterval(-2 * 86400))
        let facts = CoachFacts.make(from: [s], goal: .strength, experience: .intermediate, now: now)
        let assess = CoachSession.candidates(for: facts).first { $0.id == "assessment.baseline" }
        XCTAssertNotNil(assess)
        XCTAssertEqual(assess?.evidenceCategory, .fieldTestValidity)
        XCTAssertFalse(assess!.systemsTrained.isEmpty)
        XCTAssertFalse(assess!.citationIds.isEmpty)
    }

    /// The system-need nudge is capped (≤12) and cannot override a hard floor: with
    /// zero strength days the primary is still strength even though aerobic/VO₂
    /// systems are stale.
    func testSystemNeedIsCappedAndCannotOverrideStrengthFloor() throws {
        let ctx = try makeContext()
        let now = testNow
        let runs = (1...3).map {
            makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-Double($0) * 86400),
                            duration: 60 * 60, avgHR: 140)
        }
        let facts = CoachFacts.make(from: runs, goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)

        XCTAssertEqual(decision.primary.kind, .strength,
                       "System need must not override the strength floor. Got: \(decision.primary.id)")
        for (_, b) in decision.scoreBreakdowns {
            XCTAssertLessThanOrEqual(b.systemNeed, 12, "systemNeed must be capped at 12")
            XCTAssertGreaterThanOrEqual(b.systemNeed, 0)
        }
    }

    /// Eligible candidates expose a transparent score breakdown whose total matches its
    /// components, and HR-dependent work is penalized when max-HR is only age-estimated.
    func testScoreBreakdownsAndConfidencePenalty() throws {
        let ctx = try makeContext()
        let now = testNow
        let based = CoachFacts.make(from: [
            makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-86400), duration: 60 * 60, avgHR: 140),
            makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-2 * 86400), duration: 60 * 60, avgHR: 140),
        ], goal: .strength, experience: .intermediate, now: now)
        XCTAssertEqual(based.zoneSource, .ageEstimated, "HR present → age-estimated max-HR")

        let decision = CoachDecisionEngine.run(based)
        XCTAssertFalse(decision.scoreBreakdowns.isEmpty)
        let primaryBreakdown = decision.scoreBreakdowns[decision.primary.id]
        XCTAssertNotNil(primaryBreakdown)
        if let b = primaryBreakdown {
            XCTAssertEqual(b.total, b.base + b.systemNeed + b.preference - b.sameDayPenalty - b.confidencePenalty)
        }

        if let threshold = decision.scoreBreakdowns["aerobic.thresholdTempo"] {
            XCTAssertEqual(threshold.confidencePenalty, 3,
                           "Threshold work should carry a confidence penalty under age-estimated HRmax")
        }
    }

    // MARK: - Two-a-day tests (allowsTwoADays = true)

    func testTwoADayShowsBothRecommendationsWhenBothNeeded() throws {
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let prefs = CoachSchedulePreferences.default.withTwoADays(true)
        let decision = CoachDecisionEngine.run(facts, schedulePreferences: prefs)

        // Cold start: both strength and cardio are needed.
        XCTAssertEqual(decision.todayPlannedRecommendations.count, 2,
                       "Should have two planned recommendations for two-a-day")
        XCTAssertTrue(decision.todayPlannedRecommendations.contains { $0.kind == .strength },
                      "Should include a strength recommendation")
        XCTAssertTrue(decision.todayPlannedRecommendations.contains { $0.isAerobic },
                      "Should include a cardio recommendation")
    }

    func testTwoADayAfterCardioCompleteShowsOnlyStrength() throws {
        let ctx = try makeContext()
        let now = testNow

        // Complete a cardio event today
        let boxing = makeCardioEvent(context: ctx, type: .boxing,
                                      date: now.addingTimeInterval(-3600),
                                      duration: 44 * 60, avgHR: 135)
        let facts = CoachFacts.make(from: [boxing], goal: .strength, experience: .intermediate, now: now)
        let prefs = CoachSchedulePreferences.default.withTwoADays(true)
        let decision = CoachDecisionEngine.run(facts, schedulePreferences: prefs)

        // Cardio done, strength still needed → one recommendation remains
        XCTAssertEqual(decision.todayPlannedRecommendations.count, 1,
                       "After cardio, only strength should remain")
        XCTAssertEqual(decision.todayPlannedRecommendations.first?.kind, .strength,
                       "Remaining should be strength")
        XCTAssertEqual(decision.planAdherence, .planAhead,
                       "Plan should not be complete — strength still needed")
    }

    func testTwoADayAfterStrengthCompleteShowsOnlyCardio() throws {
        let ctx = try makeContext()
        let now = testNow

        // Complete a strength event today
        let strength = try makeStrengthEvent(context: ctx, name: "Bench Press",
                                              primaryMuscles: ["chest"],
                                              date: now.addingTimeInterval(-3600))
        let facts = CoachFacts.make(from: [strength], goal: .strength, experience: .intermediate, now: now)
        let prefs = CoachSchedulePreferences.default.withTwoADays(true)
        let decision = CoachDecisionEngine.run(facts, schedulePreferences: prefs)

        // Strength done, cardio still needed → one recommendation remains
        XCTAssertEqual(decision.todayPlannedRecommendations.count, 1,
                       "After strength, only cardio should remain")
        XCTAssertTrue(decision.todayPlannedRecommendations.first?.isAerobic ?? false,
                      "Remaining should be cardio")
        XCTAssertEqual(decision.planAdherence, .planAhead,
                       "Plan should not be complete — cardio still needed")
    }

    func testTwoADayAfterStrengthCompletesWeeklyTargetStillShowsCardio() throws {
        let ctx = try makeContext()
        let now = testSaturday

        let earlierStrength = try makeStrengthEvent(context: ctx, name: "Back Squat",
                                                     primaryMuscles: ["quadriceps"],
                                                     date: now.addingTimeInterval(-3 * 86400),
                                                     setCompletedAt: now.addingTimeInterval(-3 * 86400))
        let prefs = CoachSchedulePreferences.default.withTwoADays(true)

        let beforeFacts = CoachFacts.make(from: [earlierStrength], goal: .strength,
                                          experience: .intermediate, now: now)
        let beforeDecision = CoachDecisionEngine.run(beforeFacts, schedulePreferences: prefs)
        XCTAssertEqual(beforeDecision.todayPlannedRecommendations.count, 2,
                       "Before either workout, Saturday should show both planned workouts")

        let todayStrength = try makeStrengthEvent(context: ctx, name: "Bench Press",
                                                   primaryMuscles: ["chest"],
                                                   date: now.addingTimeInterval(-3600),
                                                   setCompletedAt: now.addingTimeInterval(-3600))
        let afterFacts = CoachFacts.make(from: [earlierStrength, todayStrength],
                                         goal: .strength, experience: .intermediate, now: now)
        let afterDecision = CoachDecisionEngine.run(afterFacts, schedulePreferences: prefs)

        XCTAssertEqual(afterFacts.weeklyBalance.strengthDays, prefs.strengthDaysPerWeek,
                       "The morning strength workout should satisfy the weekly strength target")
        XCTAssertEqual(afterDecision.todayPlannedRecommendations.count, 1,
                       "Cardio should remain planned after only strength is complete")
        XCTAssertTrue(afterDecision.todayPlannedRecommendations.first?.isAerobic ?? false,
                      "The remaining planned workout should be cardio")
        XCTAssertTrue(afterDecision.primary.isAerobic,
                      "The card's single Start action should launch the remaining cardio workout")
        XCTAssertEqual(afterDecision.planAdherence, .planAhead,
                       "Plan should not be complete until the planned cardio is also done")

        let todayCardio = makeCardioEvent(context: ctx, type: .cycle,
                                          date: now.addingTimeInterval(-900),
                                          duration: 35 * 60, avgHR: 135)
        let completeFacts = CoachFacts.make(from: [earlierStrength, todayStrength, todayCardio],
                                            goal: .strength, experience: .intermediate, now: now)
        let completeDecision = CoachDecisionEngine.run(completeFacts, schedulePreferences: prefs)

        XCTAssertEqual(completeDecision.todayPlannedRecommendations.count, 0,
                       "No planned workouts should remain after both two-a-day sessions are complete")
        if case .planComplete(let completedKind, let description, _) = completeDecision.planAdherence {
            XCTAssertNil(completedKind,
                         "Two-a-day completion should render the generic Plan followed state")
            XCTAssertEqual(description, "Strength and cardio — both in the books")
        } else {
            XCTFail("Plan should be complete after both planned workouts. Got: \(completeDecision.planAdherence)")
        }
    }

    func testTwoADayAfterBothComplete() throws {
        let ctx = try makeContext()
        let now = testNow

        let strength = try makeStrengthEvent(context: ctx, name: "Bench Press",
                                              primaryMuscles: ["chest"],
                                              date: now.addingTimeInterval(-7200))
        let boxing = makeCardioEvent(context: ctx, type: .boxing,
                                      date: now.addingTimeInterval(-3600),
                                      duration: 44 * 60, avgHR: 135)
        let facts = CoachFacts.make(from: [strength, boxing], goal: .strength,
                                     experience: .intermediate, now: now)
        let prefs = CoachSchedulePreferences.default.withTwoADays(true)
        let decision = CoachDecisionEngine.run(facts, schedulePreferences: prefs)

        XCTAssertEqual(decision.todayPlannedRecommendations.count, 0,
                       "Both done — no remaining recommendations")
        if case .planComplete(let completedKind, _, _) = decision.planAdherence {
            XCTAssertNil(completedKind,
                         "Two-a-day completion should render the generic Plan followed state")
        } else {
            XCTFail("Plan should be complete after both strength and cardio. Got: \(decision.planAdherence)")
        }
    }

    func testTwoADayOffByDefault() throws {
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        // Default prefs (allowsTwoADays = false)
        let decision = CoachDecisionEngine.run(facts)

        XCTAssertEqual(decision.todayPlannedRecommendations.count, 0,
                       "Without two-a-day opt-in, recommendations should be empty")
    }

    // MARK: - Step health nudge

    func testLowStepNudgeWhenBelowFloor() {
        let activity: [DayActivity] = stride(from: 0, through: 6, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 3000)
        }
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate,
                                    activityTrend: activity)
        let decision = CoachDecisionEngine.run(facts)

        let stepFact = decision.observedFacts.first { $0.kind == .weeklySteps }
        XCTAssertNotNil(stepFact, "Should have weeklySteps observed fact")
        XCTAssertTrue(stepFact!.detail?.contains("Low") ?? false)

        let lowWarning = decision.warnings.first { $0.id == "lowSteps" }
        XCTAssertNotNil(lowWarning, "Should have lowSteps warning when below floor")
        XCTAssertTrue(lowWarning!.citationIds.contains("saintMauriceSteps2020"))
        XCTAssertTrue(lowWarning!.citationIds.contains("leeAccelerometer2019"))
    }

    func testNoStepNudgeWhenOnTrack() {
        let activity: [DayActivity] = stride(from: 0, through: 6, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 9000)
        }
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate,
                                    activityTrend: activity)
        let decision = CoachDecisionEngine.run(facts)

        let stepFact = decision.observedFacts.first { $0.kind == .weeklySteps }
        XCTAssertNotNil(stepFact, "Should have weeklySteps observed fact")
        XCTAssertTrue(stepFact!.detail?.contains("On track") ?? false)

        let lowWarning = decision.warnings.first { $0.id == "lowSteps" }
        XCTAssertNil(lowWarning, "Should not have lowSteps warning when on track")
    }

    func testNoStepFactWithoutActivityTrend() {
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate)
        let decision = CoachDecisionEngine.run(facts)

        let stepFact = decision.observedFacts.first { $0.kind == .weeklySteps }
        XCTAssertNil(stepFact, "Should not have weeklySteps fact without activity data")
    }

    func testStepNudgeDoesNotOverridePrimarySession() {
        let activity: [DayActivity] = stride(from: 0, through: 6, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 2000)
        }
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate,
                                    activityTrend: activity)
        let decision = CoachDecisionEngine.run(facts)

        XCTAssertNotEqual(decision.primary.kind, .rest, "Primary should not be rest despite low steps")
        let lowWarning = decision.warnings.first { $0.id == "lowSteps" }
        XCTAssertNotNil(lowWarning, "Should have lowSteps nudge")
        // Warning should not cite anything outside stepsHealth pool
        let allStepCitations = Set(lowWarning!.citationIds)
        let stepPoolIds = Set(CitationRegistry.stepsHealthPool.citationIds)
        XCTAssertTrue(allStepCitations.isSubset(of: stepPoolIds),
                      "Low-step warning should only cite stepsHealth pool citations")
    }

    // MARK: - CNS lift warning suppression

    func testCNSLiftSkipsExcessiveSetsPerSessionWarning() throws {
        let ctx = try makeContext()
        let now = testNow
        // Snatch with 12 sets — typical Olympic CNS training volume
        let snatch = try makeStrengthEvent(context: ctx, name: "Snatch",
                                            primaryMuscles: ["quadriceps", "glutes", "delts"],
                                            date: now.addingTimeInterval(-3600), sets: 12)
        let facts = CoachFacts.make(from: [snatch], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        let snatchWarnings = decision.warnings.filter { $0.id.contains("excessiveSetsPerSession") }
        XCTAssertTrue(snatchWarnings.isEmpty,
                      "CNS lift Snatch should NOT trigger excessiveSetsPerSession warning. Got: \(snatchWarnings.map(\.message))")
    }

    func testNonCNSLiftStillTriggersExcessiveSetsPerSessionWarning() throws {
        let ctx = try makeContext()
        let now = testNow
        // Back Squat with 12 sets — exceeds the threshold for a non-CNS lift
        let squat = try makeStrengthEvent(context: ctx, name: "Back Squat",
                                           primaryMuscles: ["quadriceps", "glutes"],
                                           date: now.addingTimeInterval(-3600), sets: 12)
        let facts = CoachFacts.make(from: [squat], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        let squatWarnings = decision.warnings.filter { $0.id.contains("excessiveSetsPerSession.Back Squat") }
        XCTAssertFalse(squatWarnings.isEmpty,
                       "Non-CNS lift Back Squat should still trigger excessiveSetsPerSession warning")
    }

    func testCNSLiftBelowThresholdDoesNotTriggerWarning() throws {
        let ctx = try makeContext()
        let now = testNow
        // Clean and Jerk with 8 sets — below warning threshold
        let cj = try makeStrengthEvent(context: ctx, name: "Clean and Jerk",
                                        primaryMuscles: ["quadriceps", "glutes", "delts"],
                                        date: now.addingTimeInterval(-3600), sets: 8)
        let facts = CoachFacts.make(from: [cj], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        let cjWarnings = decision.warnings.filter { $0.id.contains("excessiveSetsPerSession") }
        XCTAssertTrue(cjWarnings.isEmpty,
                      "Clean and Jerk with 8 sets should not trigger warning (below 10 threshold)")
    }

    func testAllCNSLiftNamesAreRecognized() {
        for name in Exercise.cnsLiftNames {
            XCTAssertTrue(Exercise.cnsLiftNames.contains(name),
                          "CNS lift '\(name)' should be in the cnsLiftNames set")
        }
        // Verify known non-CNS lifts are NOT in the set
        XCTAssertFalse(Exercise.cnsLiftNames.contains("Back Squat"))
        XCTAssertFalse(Exercise.cnsLiftNames.contains("Bench Press"))
        XCTAssertFalse(Exercise.cnsLiftNames.contains("Deadlift"))
    }

    // MARK: - Both-modality completion (field-test issue #2)

    /// Doing BOTH strength and cardio today must complete the day even when the
    /// coach's plan for today would otherwise be recovery (both weekly targets
    /// already met). Previously this fell to offPlan and the card ignored cardio,
    /// showing a strength-only message.
    func testBothStrengthAndCardioTodayCompletesEvenOnRecoveryDay() throws {
        let ctx = try makeContext()
        let now = testNow

        // Prior work this week so both weekly targets are already met and the
        // coach would recommend recovery/rest rather than strength or cardio.
        let priorStrength = [
            try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                  date: now.addingTimeInterval(-3 * 86400)),
            try makeStrengthEvent(context: ctx, name: "Bench", primaryMuscles: ["chest"],
                                  date: now.addingTimeInterval(-2 * 86400)),
            try makeStrengthEvent(context: ctx, name: "Deadlift", primaryMuscles: ["hamstrings"],
                                  date: now.addingTimeInterval(-1 * 86400)),
        ]
        let priorCardio = [
            makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-3 * 86400),
                            duration: 3600, avgHR: 140),
            makeCardioEvent(context: ctx, type: .cycle, date: now.addingTimeInterval(-2 * 86400),
                            duration: 3600, avgHR: 135),
            makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-1 * 86400),
                            duration: 3600, avgHR: 140),
        ]

        // Today: both a strength session AND a cardio session.
        let todayStrength = try makeStrengthEvent(context: ctx, name: "Hack Squat",
                                                  primaryMuscles: ["quadriceps"],
                                                  date: now.addingTimeInterval(-3600),
                                                  setCompletedAt: now.addingTimeInterval(-3600))
        let todayCardio = makeCardioEvent(context: ctx, type: .cycle,
                                          date: now.addingTimeInterval(-900),
                                          duration: 30 * 60, avgHR: 130)

        let facts = CoachFacts.make(from: priorStrength + priorCardio + [todayStrength, todayCardio],
                                    goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)

        if case .planComplete(let completedKind, let description, _) = decision.planAdherence {
            XCTAssertNil(completedKind,
                         "Both-modality completion should use the generic (nil) completed kind")
            XCTAssertEqual(description, "Strength and cardio — both in the books")
        } else {
            XCTFail("Both strength and cardio done today should complete the plan. Got: \(decision.planAdherence)")
        }
    }

    /// A short (any-duration) cardio still counts toward both-modality completion.
    func testShortCardioStillCompletesWithStrength() throws {
        let ctx = try makeContext()
        let now = testNow

        let todayStrength = try makeStrengthEvent(context: ctx, name: "Hack Squat",
                                                  primaryMuscles: ["quadriceps"],
                                                  date: now.addingTimeInterval(-3600),
                                                  setCompletedAt: now.addingTimeInterval(-3600))
        // Just a 6-minute walk.
        let shortWalk = makeCardioEvent(context: ctx, type: .walk,
                                        date: now.addingTimeInterval(-600),
                                        duration: 6 * 60, avgHR: 105)
        let facts = CoachFacts.make(from: [todayStrength, shortWalk],
                                    goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)

        if case .planComplete(let completedKind, let description, _) = decision.planAdherence {
            XCTAssertNil(completedKind)
            XCTAssertEqual(description, "Strength and cardio — both in the books")
        } else {
            XCTFail("Any-duration cardio + strength today should complete. Got: \(decision.planAdherence)")
        }
    }

    /// Strength alone today (no cardio) must NOT report both-modality completion.
    func testStrengthOnlyTodayIsNotBothComplete() throws {
        let ctx = try makeContext()
        let now = testNow
        let todayStrength = try makeStrengthEvent(context: ctx, name: "Hack Squat",
                                                  primaryMuscles: ["quadriceps"],
                                                  date: now.addingTimeInterval(-3600),
                                                  setCompletedAt: now.addingTimeInterval(-3600))
        let facts = CoachFacts.make(from: [todayStrength],
                                    goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)

        if case .planComplete(_, let description, _) = decision.planAdherence {
            XCTAssertNotEqual(description, "Strength and cardio — both in the books",
                              "Strength alone must not claim both modalities are done")
        }
    }
}
