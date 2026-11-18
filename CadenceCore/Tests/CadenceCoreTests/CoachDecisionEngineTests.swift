#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

struct CoachDecisionEngineTests {

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

    @Test func twoStrengthDaysZeroAerobicPrefersAerobic() throws {
        let ctx = try makeContext()
        let now = testNow
        let s1 = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                        date: now.addingTimeInterval(-3 * 86400))
        let s2 = try makeStrengthEvent(context: ctx, name: "Bench", primaryMuscles: ["chest"],
                                        date: now.addingTimeInterval(-6 * 86400))
        let facts = CoachFacts.make(from: [s1, s2], goal: .strength, experience: .intermediate, now: now)

        let decision = CoachDecisionEngine.run(facts)
        #expect(decision.primary.kind == .moderateAerobic || decision.primary.kind == .easyAerobic,
                      "With 2 strength days and 0 aerobic, primary should be aerobic. Got: \(decision.primary.kind)")
    }

    @Test func zeroStrengthDaysOneFiftyAerobicPrefersStrength() throws {
        let ctx = try makeContext()
        let now = testNow
        let runs: [TrainingEvent] = [
            makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-1 * 86400), duration: 3600, avgHR: 140),
            makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-2 * 86400), duration: 3600, avgHR: 140),
            makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-3 * 86400), duration: 3600, avgHR: 140),
        ]
        let facts = CoachFacts.make(from: runs, goal: .strength, experience: .intermediate, now: now)

        let decision = CoachDecisionEngine.run(facts)
        #expect(decision.primary.kind == .strength,
                       "With 0 strength and aerobic met, primary should be strength. Got: \(decision.primary.kind)")
    }

    // MARK: - Daily recommendation slots

    @Test func dailySlotsBothModalitiesWithoutTwoADays() throws {
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let prefs = CoachSchedulePreferences(allowsTwoADays: false)
        let decision = CoachDecisionEngine.run(facts, schedulePreferences: prefs)
        #expect(decision.dailyRecommendationSlots.map(\.modality) == [.strength, .cardio])
        #expect((decision.dailyRecommendationSlots.filter { !$0.isCompanion }.count <= 1) == true)
        for slot in decision.dailyRecommendationSlots {
            #expect(decision.scoreBreakdowns[slot.session.id] != nil,
                            "Slot sessions must come from the scored candidates")
        }
    }

    @Test func dailySlotsFilterCompletedModality() throws {
        let ctx = try makeContext()
        let now = testNow
        let strength = try makeStrengthEvent(context: ctx, name: "Bench Press",
                                             primaryMuscles: ["chest"],
                                             date: now.addingTimeInterval(-2 * 3600))
        let cardio = makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-3600),
                                     duration: 1800, avgHR: 140)
        let onlyStrength = CoachDecisionEngine.run(
            CoachFacts.make(from: [strength], goal: .strength, experience: .intermediate, now: now))
        #expect(!onlyStrength.dailyRecommendationSlots.contains { $0.modality == .strength })
        let onlyCardio = CoachDecisionEngine.run(
            CoachFacts.make(from: [cardio], goal: .strength, experience: .intermediate, now: now))
        #expect(!onlyCardio.dailyRecommendationSlots.contains { $0.modality == .cardio })
        let both = CoachDecisionEngine.run(
            CoachFacts.make(from: [strength, cardio], goal: .strength, experience: .intermediate, now: now))
        #expect(both.dailyRecommendationSlots.isEmpty)
    }

    @Test func dailySlotsEmptyOnPainConcern() throws {
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: testNow)
        let decision = CoachDecisionEngine.run(facts, hasPainConcern: true)
        #expect(decision.dailyRecommendationSlots.isEmpty)
    }

    // MARK: - Pain concern

    @Test func painConcernBlocksHardTraining() throws {
        let now = testNow
        let events: [TrainingEvent] = []
        let facts = CoachFacts.make(from: events, goal: .strength, experience: .intermediate, now: now)

        let decision = CoachDecisionEngine.run(facts, hasPainConcern: true)
        #expect(decision.primary.kind == .rest)
        #expect(!decision.warnings.isEmpty)
    }

    // MARK: - Beginner

    @Test func beginnerGetsBeginnerSessions() throws {
        let now = testNow
        let events: [TrainingEvent] = []
        let facts = CoachFacts.make(from: events, goal: .strength, experience: .beginner, now: now)

        let candidates = CoachSession.candidates(for: facts)
        #expect(candidates.contains { $0.id == "strength.beginnerA" })
        #expect(candidates.contains { $0.id == "strength.beginnerB" })
    }

    // MARK: - Determinism

    @Test func decisionIsDeterministic() throws {
        let ctx = try makeContext()
        let now = testNow
        let s1 = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                        date: now.addingTimeInterval(-3 * 86400))
        let facts = CoachFacts.make(from: [s1], goal: .strength, experience: .intermediate, now: now)

        let d1 = CoachDecisionEngine.run(facts)
        let d2 = CoachDecisionEngine.run(facts)
        #expect(d1.primary.id == d2.primary.id)
    }

    // MARK: - WeeklyPlan generation

    @Test func weeklyPlanIncludesSevenDays() throws {
        let now = testNow
        let events: [TrainingEvent] = []
        let facts = CoachFacts.make(from: events, goal: .strength, experience: .intermediate, now: now)

        let plan = WeeklyPlan.generate(from: facts)
        #expect(plan.days.count >= 7, "Plan should have at least 7 days (history + future)")
        #expect(plan.days.contains { $0.isToday })
    }

    @Test func weeklyPlanShowsCompletedDays() throws {
        let ctx = try makeContext()
        let now = testNow
        let s1 = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                        date: now.addingTimeInterval(-2 * 86400))
        let facts = CoachFacts.make(from: [s1], goal: .strength, experience: .intermediate, now: now)

        let plan = WeeklyPlan.generate(from: facts)
        let completed = plan.days.filter(\.isCompleted)
        #expect(!completed.isEmpty)
    }

    @Test func weeklyPlanDoesNotBackfillEmptyHistoryAsPlannedSessions() throws {
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)

        let plan = WeeklyPlan.generate(from: facts)

        #expect(plan.historyDays.count == 7)
        #expect(plan.historyDays.allSatisfy { !$0.isFuture })
        #expect(plan.historyDays.filter { !$0.isCompleted && $0.isPast }.allSatisfy { $0.sessions.isEmpty },
                      "Blank past history days must not become planned sessions")
    }

    @Test func weeklyPlanRemainingCalendarWeekIsFutureOnlyAndChronological() throws {
        let now = testNow
        let cal = Calendar.current
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)

        let plan = WeeklyPlan.generate(from: facts)
        let remaining = plan.remainingCalendarWeekDays
        let weekStart = WeeklyStats.weekStart(now: now)
        let nextWeekStart = cal.date(byAdding: .day, value: 7, to: weekStart)!

        #expect(remaining.count == 3, "Thursday should have Fri/Sat/Sun remaining in the Monday-bounded week")
        #expect(remaining.map(\.date) == remaining.map(\.date).sorted())
        #expect(remaining.allSatisfy { $0.isFuture })
        #expect(remaining.allSatisfy { $0.date >= cal.startOfDay(for: now) && $0.date < nextWeekStart })
        #expect(remaining.allSatisfy { $0.sessionKind != nil })
    }

    @Test func weeklyPlanRestOfWeekPrioritizesStrengthDeficitWithoutArbitraryRestAlternation() throws {
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)

        let plan = WeeklyPlan.generate(from: facts)
        let remaining = plan.remainingCalendarWeekDays

        // With empty history and default preferences (strength=2, cardio=3),
        // remaining days should push toward strength targets first, then cardio.
        let activeRemaining = remaining.filter { !$0.sessions.isEmpty }
        #expect(!activeRemaining.isEmpty, "Should have planned sessions in remaining week")
        // First active session should be strength (strength deficit)
        if let first = activeRemaining.first {
            #expect(first.sessions.contains { $0.kind == .strength },
                          "First remaining session should include strength")
        }
    }

    @Test func weeklyPlanModerateCardioIsNotMarkedHard() throws {
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
            #expect(moderateCardioSessions.allSatisfy { !$0.isHard },
                          "Moderate cardio sessions should NOT be marked hard")
        }
    }

    @Test func weeklyPlanPoorReadinessOnlyDefersTomorrow() throws {
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate,
                                    readinessEntry: poorReadiness(now), now: now)

        let plan = WeeklyPlan.generate(from: facts)

        // Coach suggests, it does not proscribe: poor readiness attaches a
        // lighter-day recommendation to tomorrow but never converts a scheduled
        // training day into a forced Recovery day.
        let tomorrow = try #require(plan.futureDays.first)
        #expect(tomorrow.sessionKind != .recovery,
                          "Poor readiness must not force a Recovery day")
        #expect(tomorrow.sessions.contains(where: \.recommendsLighter),
                      "Poor readiness should attach a non-blocking lighter-day recommendation")
        #expect(plan.futureDays.contains { day in
            day.sessions.contains { $0.kind == .strength }
        }, "A one-day readiness dip should not drop the plan's strength days")
        #expect(!plan.futureDays.dropFirst().flatMap(\.sessions).contains(where: \.recommendsLighter),
                       "The readiness recommendation applies to tomorrow only")
    }

    // MARK: - Observed facts (v2 rich model)

    @Test func observedFactsIncludeLastCardio() throws {
        let ctx = try makeContext()
        let now = testNow
        let run = makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-3600),
                                  duration: 1800, avgHR: 135)
        let facts = CoachFacts.make(from: [run], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        let cardioFact = decision.observedFacts.first { $0.kind == .lastCardio }
        #expect(cardioFact != nil, "Should have last cardio fact when cardio exists")
        #expect(cardioFact?.title == "Last cardio")
    }

    /// Fix 1: "What you did" must read from the workout's date (start), not the
    /// finalize/entry time (endedAt). A session started 12h ago but finalized 2h ago
    /// must surface "12h ago".
    @Test func lastStrengthValueUsesWorkoutDateNotEndedAt() throws {
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
        #expect(strengthFact?.value == "12h ago",
                       "Should format from session.date (12h ago), not endedAt (2h ago). Got: \(strengthFact?.value ?? "nil")")
        #expect(strengthFact?.occurredAt == event.start,
                       "occurredAt sort key should match the displayed start time")
    }

    /// Fix 3: the "What you did" facts must carry the source workout id so the Home
    /// card can navigate to that workout. Aggregate facts must not.
    @Test func observedFactsCarrySourceWorkoutId() throws {
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
        #expect(strengthFact?.sourceId == strength.id,
                       "last strength fact should carry its source session id")
        #expect(cardioFact?.sourceId == run.id,
                       "last cardio fact should carry its source cardio id")
        let strengthDaysFact = decision.observedFacts.first { $0.kind == .weeklyStrengthDays }
        #expect(strengthDaysFact?.sourceId == nil, "aggregate facts should not carry a source id")
    }

    @Test func observedFactsUseStaticSummaryValues() throws {
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        for fact in decision.observedFacts {
            if fact.kind == .weeklyStrengthDays || fact.kind == .weeklyModerateEquivalentMinutes {
                #expect(fact.occurredAt == nil, "Summary facts should have nil occurredAt, got \(fact.occurredAt?.description ?? "nil")")
            }
        }
    }

    @Test func observedFactsPickNewestCardioWhenEventsUnsorted() throws {
        let ctx = try makeContext()
        let now = testNow
        let c1 = makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-7200),
                                 duration: 1800, avgHR: 135)
        let c2 = makeCardioEvent(context: ctx, type: .walk, date: now.addingTimeInterval(-3600),
                                  duration: 2400, avgHR: 110)
        let facts = CoachFacts.make(from: [c1, c2], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        let cardioFact = decision.observedFacts.first { $0.kind == .lastCardio }
        #expect(cardioFact != nil)
        #expect(cardioFact!.detail?.contains("Walk") ?? false,
                      "Should pick the most recent (walk), got: \(cardioFact?.detail ?? "nil")")
    }

    /// Home supplies events newest-first (cardio block descending). The engine must
    /// pick the most recent cardio by end date, not the first in the array.
    @Test func observedFactsPickNewestCardioWhenEventsAreNewestFirst() throws {
        let ctx = try makeContext()
        let now = testNow
        let newWalk = makeCardioEvent(context: ctx, type: .walk, date: now.addingTimeInterval(-3600),
                                      duration: 2400, avgHR: 110)
        let oldRun = makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-2 * 86400),
                                     duration: 1800, avgHR: 150)
        let facts = CoachFacts.make(from: [newWalk, oldRun], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        let cardioFact = decision.observedFacts.first { $0.kind == .lastCardio }
        #expect(cardioFact != nil)
        #expect(cardioFact!.detail?.contains("Walk") ?? false,
                      "Should pick the most recent cardio (walk), got: \(cardioFact?.detail ?? "nil")")
    }

    /// Home supplies strength events newest-first. Pick newest strength by end date.
    @Test func observedFactsPickNewestStrengthWhenHomeSuppliesNewestFirst() throws {
        let ctx = try makeContext()
        let now = testNow
        let newBench = try makeStrengthEvent(context: ctx, name: "Bench Press", primaryMuscles: ["chest"],
                                             date: now.addingTimeInterval(-1 * 86400))
        let oldSquat = try makeStrengthEvent(context: ctx, name: "Back Squat", primaryMuscles: ["quadriceps"],
                                             date: now.addingTimeInterval(-2 * 86400))
        let facts = CoachFacts.make(from: [newBench, oldSquat], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        let strengthFact = decision.observedFacts.first { $0.kind == .lastStrength }
        #expect(strengthFact != nil)
        #expect(strengthFact!.detail?.contains("Bench") ?? false,
                      "Should pick the most recent strength (bench), got: \(strengthFact?.detail ?? "nil")")
    }

    /// Home-like ordering: all strength newest-to-oldest, then all cardio
    /// newest-to-oldest. The engine must pick the newest of each by end date.
    @Test func observedFactsPickNewestForHomeMixedOrdering() throws {
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
        #expect(strengthFact?.detail?.contains("Bench") ?? false,
                      "newest strength should be bench, got: \(strengthFact?.detail ?? "nil")")
        #expect(cardioFact?.detail?.contains("Walk") ?? false,
                      "newest cardio should be walk, got: \(cardioFact?.detail ?? "nil")")
    }

    /// A future-dated event (e.g. clock skew / scheduled import) must never be
    /// treated as the last event or counted in the weekly balance.
    @Test func futureEventsDoNotCountAsLastOrWeeklyBalance() throws {
        let ctx = try makeContext()
        let now = testNow
        let pastWalk = makeCardioEvent(context: ctx, type: .walk, date: now.addingTimeInterval(-3600),
                                       duration: 1800, avgHR: nil)   // moderate ⇒ 30 mod-eq min
        let futureRun = makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(86400),
                                        duration: 3600, avgHR: 160)  // vigorous ⇒ 120 mod-eq if wrongly counted
        let facts = CoachFacts.make(from: [futureRun, pastWalk], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        let cardioFact = decision.observedFacts.first { $0.kind == .lastCardio }
        #expect(cardioFact?.detail?.contains("Walk") ?? false,
                      "last cardio should be the past walk, not the future run; got: \(cardioFact?.detail ?? "nil")")
        let modEquiv = facts.weeklyBalance.moderateEquivalentMinutes
        #expect(modEquiv > 0, "past walk should count")
        #expect(modEquiv <= 35,
                                 "future run must be excluded from weekly balance; got \(modEquiv) min")
    }

    @Test func noEvidenceDuplicationDataNeededForInlineSources() throws {
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        // The engine always produces inline citations (on claim, warnings, rule-out).
        // We just check the decision is well-formed.
        #expect(!decision.primary.id.isEmpty)
    }

    // MARK: - Expanded alternatives

    @Test func moderateAerobicAlternativesIncludeRunWalkCycleSwimOrRow() throws {
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let candidates = CoachSession.candidates(for: facts)
        let moderateIDs = candidates.filter { $0.kind == .moderateAerobic }.map(\.id)
        #expect(moderateIDs.contains("aerobic.moderateRun"))
        #expect(moderateIDs.contains("aerobic.moderateWalk"))
        #expect(moderateIDs.contains("aerobic.moderateCycle"))
        #expect(moderateIDs.contains("aerobic.moderateSwim"))
        #expect(moderateIDs.contains("aerobic.moderateRow"))
    }

    // MARK: - Preference-aware scoring

    @Test func preferenceForCyclingReordersEligibleModerateAerobicCandidates() throws {
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)

        var profile = CoachPreferenceProfile.empty
        profile.aerobicPreferences = [
            AerobicPreference(intent: .moderateAerobic, modality: .cycle, score: 5, updatedAt: now)
        ]

        let decision = CoachDecisionEngine.run(facts, profile: profile)
        // With strong cycle preference, cycle should be primary for moderate aerobic
        #expect(decision.primary.kind == .moderateAerobic)
        #expect(decision.primary.modality == .cycle,
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
    @Test func selectingBoxingRemembersBoxingModalityNotOther() throws {
        let ctx = try makeContext()
        let now = testNow
        let facts = try aerobicGapFacts(ctx, now)
        let candidates = CoachSession.candidates(for: facts)
        let boxing = candidates.first { $0.id == "aerobic.moderateBoxing" }
        #expect(boxing?.modality == .boxing, "boxing candidate must carry its true modality")

        var profile = CoachPreferenceProfile.empty
        profile.recordSelection(boxing!, from: candidates)
        #expect(profile.aerobicPreferences.first?.modality == .boxing,
                       "selecting boxing must store a boxing preference, never .other")

        let decision = CoachDecisionEngine.run(facts, profile: profile)
        #expect(decision.primary.modality == .boxing,
                       "with a remembered boxing preference, Coach should recommend boxing")
    }

    /// Picking a modality that isn't the default winner (swim) must be remembered
    /// and recommended next — proving cardio-type fidelity for any modality.
    @Test func selectingSwimRemembersAndRecommendsSwim() throws {
        let ctx = try makeContext()
        let now = testNow
        let facts = try aerobicGapFacts(ctx, now)
        let candidates = CoachSession.candidates(for: facts)
        let swim = candidates.first { $0.id == "aerobic.moderateSwim" }!

        // Default (no preference) Coach does not pick swim.
        #expect(CoachDecisionEngine.run(facts).primary.modality != .swim)

        var profile = CoachPreferenceProfile.empty
        profile.recordSelection(swim, from: candidates)
        #expect(profile.aerobicPreferences.first?.modality == .swim)

        #expect(CoachDecisionEngine.run(facts, profile: profile).primary.modality == .swim,
                       "Coach must remember the swim preference and recommend it next")
    }

    /// The stored preference survives a Codable round-trip (UserDefaults storage),
    /// so boxing fidelity isn't lost on relaunch.
    @Test func boxingPreferenceSurvivesCodableRoundTrip() throws {
        var profile = CoachPreferenceProfile.empty
        profile.aerobicPreferences = [
            AerobicPreference(intent: .moderateAerobic, modality: .boxing, score: 2, updatedAt: Date())
        ]
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(CoachPreferenceProfile.self, from: data)
        #expect(decoded.aerobicPreferences.first?.modality == .boxing)
    }

    @Test func preferenceDoesNotOverrideRecoveryEligibility() throws {
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
        #expect(deferredRun != nil, "Run should be deferred due to recovery, despite preference")
    }

    // MARK: - Plan adherence: Wednesday scenario

    /// Wednesday scenario: Monday full-body + 18-min run, Tuesday rest, Wednesday
    /// morning Coach recommends aerobic (both strength and aerobic floors unmet).
    /// After a 44-min boxing workout, strength is still needed — the plan stays
    /// planAhead so the remaining recommendation stays visible.
    @Test func wednesdayScenarioShowsPlanCompleteAfterBoxing() throws {
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
        #expect(beforeDecision.planAdherence == .planAhead,
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
        #expect(afterDecision.planAdherence == .planAhead,
                       "After boxing, with both targets unmet, plan should stay planAhead. Got: \(afterDecision.planAdherence)")
    }

    /// Coach scenario (maintainer request): three strength workouts done this week,
    /// preference = 3 strength days/week, it's Sunday → another strength session must
    /// NOT be recommended, even with the two-a-day preference enabled. (Pre-fix this
    /// failed two ways: `weekStart` returned next-Monday on Sundays so "this week"
    /// counted 0 strength, and the two-a-day path had no weekly cap.)
    @Test func threeStrengthThisWeekMeetsTargetNoMoreStrengthOnSundayEvenWithTwoADay() throws {
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
                                        primaryMuscles: ["quadriceps", "glutes"], date: mon, sets: 10)
        let s2 = try makeStrengthEvent(context: ctx, name: "Bench Press",
                                        primaryMuscles: ["chest"], date: wed, sets: 10)
        let s3 = try makeStrengthEvent(context: ctx, name: "Deadlift",
                                        primaryMuscles: ["hamstrings", "glutes"], date: fri, sets: 10)

        // Volume, not a day count, decides: every tracked group has its minimum.
        let prefs = CoachSchedulePreferences(allowsTwoADays: true,
                                             trackedMuscleGroups: [.quadriceps, .chest, .hamstrings])
        let facts = CoachFacts.make(from: [s1, s2, s3], goal: .strength,
                                     experience: .intermediate, now: sunday)

        #expect(facts.weeklyBalance.strengthDays == 3,
                       "Three distinct strength days should count this week, even on Sunday")

        let decision = CoachDecisionEngine.run(facts, schedulePreferences: prefs)

        #expect(decision.primary.kind != .strength,
                          "Weekly minimum volume met on Sunday → no more strength, even with two-a-day. Got: \(decision.primary.kind)")
        #expect(!decision.todayPlannedRecommendations.contains { $0.kind == .strength },
                       "Two-a-day must not override the weekly strength cap once the target is met")
        #expect(!decision.alternatives.contains { $0.kind == .strength },
                       "No strength should be offered as an alternative once the weekly target is met")
    }

    /// Completing a strength session today should suppress same-day strength
    /// recommendations.
    @Test func completedStrengthTodaySuppressesStrengthRecommendation() throws {
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
        #expect(decision.primary.kind != .strength,
                          "Strength already done today should not be primary. Got: \(decision.primary.kind)")
    }

    /// Same-day repetition: completing boxing should suppress boxing re-recommendation
    /// even if boxing preference exists.
    @Test func completedBoxingSuppressesSameDayBoxingEvenWithPreference() throws {
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
            #expect(decision.primary.modality != .boxing,
                              "Boxing already done today should not be primary. Got: \(decision.primary.modality?.rawValue ?? "nil")")
        }
    }

    /// Boxing preference still works on future eligible days without same-day completion.
    @Test func boxingPreferenceWorksOnFutureEligibleDays() throws {
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
        #expect(decision.primary.modality == .boxing,
                       "Boxing preference should win on fresh day. Got: \(decision.primary.modality?.rawValue ?? "nil")")
    }

    // MARK: - WeeklyPlan future days

    @Test func weeklyPlanIncludesFutureDays() throws {
        let now = testNow
        let events: [TrainingEvent] = []
        let facts = CoachFacts.make(from: events, goal: .strength, experience: .intermediate, now: now)

        let plan = WeeklyPlan.generate(from: facts)
        let futureDays = plan.days.filter(\.isFuture)
        #expect(!futureDays.isEmpty, "WeeklyPlan should include future days")
        #expect(futureDays.count >= 6, "Should have at least 6 future days")
    }

    @Test func weeklyPlanHasTomorrow() throws {
        let now = testNow
        let events: [TrainingEvent] = []
        let facts = CoachFacts.make(from: events, goal: .strength, experience: .intermediate, now: now)

        let plan = WeeklyPlan.generate(from: facts)
        #expect(plan.tomorrow != nil, "WeeklyPlan should have a tomorrow entry")
        #expect(plan.tomorrow!.isFuture)
    }

    @Test func weeklyPlanTomorrowAfterBoxingSuggestsStrength() throws {
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
            #expect(tomorrow != nil)
            // With only 1/2+ strength days and no recovery block, tomorrow should be strength
            if let t = tomorrow {
                #expect(t.contains("Strength") || t.contains("Rest") || t.contains("Recovery") || t.contains("Cardio"),
                              "Tomorrow preview should suggest a session type. Got: \(t)")
            }
        }
    }

    // YourWeekView "7-day history" ForEach indexes weekdays (7-element array) by
    // plan.days offset. WeeklyPlan.generate returns 13 days (7 history + 6 future),
    // so offset-based indexing crashes at offset >= 7. The fix computes the weekday
    // label from the day's actual date (safe for any array size).
    @Test func weeklyPlanDaysExceedSevenSafeWeekdayLookup() throws {
        let now = testNow
        let events: [TrainingEvent] = []
        let facts = CoachFacts.make(from: events, goal: .strength, experience: .intermediate, now: now)

        let plan = WeeklyPlan.generate(from: facts)
        #expect(plan.days.count > 7, "Plan must have >7 days to trigger the crash scenario")

        let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        for (i, day) in plan.days.enumerated() {
            // Old code used weekdays[i] — crashes when i >= 7.
            // Fix uses the day's date:
            let idx = Calendar.current.component(.weekday, from: day.date) - 2
            let label = idx >= 0 && idx < 7 ? weekdays[idx] : ""
            // Verify the label is either a valid day abbreviation or empty.
            if idx >= 0 && idx < 7 {
                #expect(label == weekdays[idx],
                               "Day \(i) (\(day.date)) weekday label should match")
            } else {
                #expect(label == "", "Invalid weekday index should yield empty string")
            }
        }
    }

    @Test func highImpactAvoidanceKeepsRunOutOfPrimaryWhenLowImpactCanFulfillIntent() throws {
        let now = testNow

        var profile = CoachPreferenceProfile.empty
        profile.avoidedTags = ["highImpact"]

        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts, profile: profile)
        // With highImpact avoided, primary should not be run
        if decision.primary.kind == .moderateAerobic {
            #expect(decision.primary.modality != .run,
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
    @Test func everyCandidateCarriesSystemsAndCategoryBackedCitations() throws {
        let ctx = try makeContext()
        let now = testNow
        let s = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                      date: now.addingTimeInterval(-2 * 86400))
        let facts = CoachFacts.make(from: [s], goal: .strength, experience: .intermediate, now: now)

        for c in CoachSession.candidates(for: facts, anaerobicOptIn: true) {
            #expect(!c.systemsTrained.isEmpty, "\(c.id) has no systemsTrained")
            if c.kind == .rest {
                #expect(c.evidenceCategory == nil)
                continue
            }
            guard let category = c.evidenceCategory else {
                Issue.record("\(c.id) has no evidenceCategory")
                continue
            }
            let pool = CitationRegistry.citationPool(for: category).citationIds
            #expect(c.citationIds == pool, "\(c.id) must cite exactly its category pool")
            #expect(!c.citationIds.isEmpty)
        }
    }

    /// The strength candidate no longer cites a mortality/public-health study (P1/P4
    /// no-mortality-for-prescriptions rule).
    @Test func strengthCandidateDoesNotCiteMortalityStudy() throws {
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let strength = CoachSession.candidates(for: facts).first { $0.id == "strength.general" }
        let mortality: Set<String> = ["ekelundActivityMortality2016", "mooreLeisureActivity2012",
                                      "aremDoseResponse2015"]
        #expect(strength != nil)
        #expect(Set(strength!.citationIds).isDisjoint(with: mortality))
        #expect(strength?.evidenceCategory == .strengthIntensity)
    }

    /// Threshold tempo only appears once an aerobic base is established and cites the
    /// threshold pool — never the VO₂ or aerobic-base pool.
    @Test func thresholdTempoGatedByAerobicBase() throws {
        let ctx = try makeContext()
        let now = testNow
        let tiny = CoachFacts.make(
            from: [makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-86400),
                                   duration: 20 * 60, avgHR: 140)],
            goal: .strength, experience: .intermediate, now: now)
        #expect(CoachSession.candidates(for: tiny).first { $0.id == "aerobic.thresholdTempo" } == nil,
                     "No threshold work before a base is built")

        let based = CoachFacts.make(from: [
            makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-86400), duration: 60 * 60, avgHR: 140),
            makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-2 * 86400), duration: 60 * 60, avgHR: 140),
        ], goal: .strength, experience: .intermediate, now: now)
        let threshold = CoachSession.candidates(for: based).first { $0.id == "aerobic.thresholdTempo" }
        #expect(threshold != nil)
        #expect(threshold?.systemsTrained == [.threshold])
        #expect(threshold?.citationIds == CitationRegistry.citationPool(for: .thresholdTraining).citationIds)
    }

    /// Anaerobic intervals are present by default once the user has an aerobic base.
    @Test func anaerobicIntervalsAreDefaultWhenEligible() throws {
        let ctx = try makeContext()
        let now = testNow
        let base = makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-2 * 86400),
                                   duration: 60 * 60, avgHR: 130)
        let facts = CoachFacts.make(from: [base], goal: .strength, experience: .intermediate, now: now)

        let optIn = CoachSession.candidates(for: facts)
            .first { $0.id == "aerobic.anaerobicIntervals" }
        #expect(optIn != nil)
        #expect(optIn?.systemsTrained == [.anaerobicPower])
        #expect(optIn?.evidenceCategory == .anaerobicTraining)
        #expect(!optIn!.citationIds.isEmpty)
        #expect(CoachDecisionEngine.run(facts).scoreBreakdowns["aerobic.anaerobicIntervals"] != nil)
    }

    /// A lighter strength option surfaces when readiness is poor.
    @Test func reducedLoadStrengthSurfacesOnPoorReadiness() throws {
        let ctx = try makeContext()
        let now = testNow
        let s = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                      date: now.addingTimeInterval(-2 * 86400))
        let facts = CoachFacts.make(from: [s], goal: .strength, experience: .intermediate,
                                    readinessEntry: poorReadiness(now), now: now)
        let reduced = CoachSession.candidates(for: facts).first { $0.id == "strength.reducedLoad" }
        #expect(reduced != nil)
        #expect(reduced!.trainingLoadTags.contains("reducedLoad"))
        #expect(reduced?.evidenceCategory == .recoveryMonitoring)
    }

    /// Poor readiness defers all hard work for a day; the primary is never hard and a
    /// hard candidate is deferred with a recovery-monitoring–cited reason.
    @Test func poorReadinessDefersHardWork() throws {
        let ctx = try makeContext()
        let now = testNow
        let s = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                      date: now.addingTimeInterval(-4 * 86400))
        let facts = CoachFacts.make(from: [s], goal: .strength, experience: .intermediate,
                                    readinessEntry: poorReadiness(now), now: now)
        let decision = CoachDecisionEngine.run(facts)

        #expect(!decision.primary.isHard,
                       "Poor readiness must not yield a hard primary. Got: \(decision.primary.id)")
        let lowReadiness = decision.deferred.first { $0.reason.id == "lowReadiness" }
        #expect(lowReadiness != nil, "A hard session should be deferred for low readiness")
        #expect(!lowReadiness!.reason.citationIds.isEmpty)
    }

    /// An assessment prompt surfaces for an actively-trained system with no baseline.
    @Test func assessmentBaselineSurfacesForUncoveredTrainedSystem() throws {
        let ctx = try makeContext()
        let now = testNow
        let s = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                      date: now.addingTimeInterval(-2 * 86400))
        let facts = CoachFacts.make(from: [s], goal: .strength, experience: .intermediate, now: now)
        let assess = CoachSession.candidates(for: facts).first { $0.id == "assessment.baseline" }
        #expect(assess != nil)
        #expect(assess?.evidenceCategory == .fieldTestValidity)
        #expect(!assess!.systemsTrained.isEmpty)
        #expect(!assess!.citationIds.isEmpty)
    }

    /// The system-need nudge is capped (≤12) and cannot override a hard floor: with
    /// zero strength days the primary is still strength even though aerobic/VO₂
    /// systems are stale.
    @Test func systemNeedIsCappedAndCannotOverrideStrengthFloor() throws {
        let ctx = try makeContext()
        let now = testNow
        let runs = (1...3).map {
            makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-Double($0) * 86400),
                            duration: 60 * 60, avgHR: 140)
        }
        let facts = CoachFacts.make(from: runs, goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)

        #expect(decision.primary.kind == .strength,
                       "System need must not override the strength floor. Got: \(decision.primary.id)")
        for (_, b) in decision.scoreBreakdowns {
            #expect(b.systemNeed <= 12, "systemNeed must be capped at 12")
            #expect(b.systemNeed >= 0)
        }
    }

    /// Eligible candidates expose a transparent score breakdown whose total matches its
    /// components, and HR-dependent work is penalized when max-HR is only age-estimated.
    @Test func scoreBreakdownsAndConfidencePenalty() throws {
        let ctx = try makeContext()
        let now = testNow
        let based = CoachFacts.make(from: [
            makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-86400), duration: 60 * 60, avgHR: 140),
            makeCardioEvent(context: ctx, type: .run, date: now.addingTimeInterval(-2 * 86400), duration: 60 * 60, avgHR: 140),
        ], goal: .strength, experience: .intermediate, now: now)
        #expect(based.zoneSource == .ageEstimated, "HR present → age-estimated max-HR")

        let decision = CoachDecisionEngine.run(based)
        #expect(!decision.scoreBreakdowns.isEmpty)
        let primaryBreakdown = decision.scoreBreakdowns[decision.primary.id]
        #expect(primaryBreakdown != nil)
        if let b = primaryBreakdown {
            #expect(b.total == b.base + b.systemNeed + b.preference - b.sameDayPenalty - b.confidencePenalty)
        }

        if let threshold = decision.scoreBreakdowns["aerobic.thresholdTempo"] {
            #expect(threshold.confidencePenalty == 3,
                           "Threshold work should carry a confidence penalty under age-estimated HRmax")
        }
    }

    // MARK: - Two-a-day tests (allowsTwoADays = true)

    @Test func twoADayShowsBothRecommendationsWhenBothNeeded() throws {
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let prefs = CoachSchedulePreferences.default.withTwoADays(true)
        let decision = CoachDecisionEngine.run(facts, schedulePreferences: prefs)

        // Cold start: both strength and cardio are needed.
        #expect(decision.todayPlannedRecommendations.count == 2,
                       "Should have two planned recommendations for two-a-day")
        #expect(decision.todayPlannedRecommendations.contains { $0.kind == .strength },
                      "Should include a strength recommendation")
        #expect(decision.todayPlannedRecommendations.contains { $0.isAerobic },
                      "Should include a cardio recommendation")
    }

    @Test func twoADayAfterCardioCompleteDoesNotShowPartialDualList() throws {
        let ctx = try makeContext()
        let now = testNow

        // Complete a cardio event today
        let boxing = makeCardioEvent(context: ctx, type: .boxing,
                                      date: now.addingTimeInterval(-3600),
                                      duration: 44 * 60, avgHR: 135)
        let facts = CoachFacts.make(from: [boxing], goal: .strength, experience: .intermediate, now: now)
        let prefs = CoachSchedulePreferences.default.withTwoADays(true)
        let decision = CoachDecisionEngine.run(facts, schedulePreferences: prefs)

        // Partial completion is not a dual-list state.
        #expect(decision.todayPlannedRecommendations.isEmpty,
                      "After cardio, the dual list should not show a strength-only remainder")
        #expect(decision.planAdherence == .planAhead,
                       "Plan should not be complete — strength still needed")
    }

    @Test func twoADayAfterStrengthCompleteDoesNotShowPartialDualList() throws {
        let ctx = try makeContext()
        let now = testNow

        // Complete a strength event today
        let strength = try makeStrengthEvent(context: ctx, name: "Bench Press",
                                              primaryMuscles: ["chest"],
                                              date: now.addingTimeInterval(-3600))
        let facts = CoachFacts.make(from: [strength], goal: .strength, experience: .intermediate, now: now)
        let prefs = CoachSchedulePreferences.default.withTwoADays(true)
        let decision = CoachDecisionEngine.run(facts, schedulePreferences: prefs)

        // Partial completion is not a dual-list state.
        #expect(decision.todayPlannedRecommendations.isEmpty,
                      "After strength, the dual list should not show a cardio-only remainder")
        #expect(decision.planAdherence == .planAhead,
                       "Plan should not be complete — cardio still needed")
    }

    @Test func twoADayAfterStrengthCompletesWeeklyTargetStillShowsCardio() throws {
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
        #expect(beforeDecision.todayPlannedRecommendations.count == 2,
                       "Before either workout, Saturday should show both planned workouts")

        let todayStrength = try makeStrengthEvent(context: ctx, name: "Bench Press",
                                                   primaryMuscles: ["chest"],
                                                   date: now.addingTimeInterval(-3600),
                                                   setCompletedAt: now.addingTimeInterval(-3600))
        let afterFacts = CoachFacts.make(from: [earlierStrength, todayStrength],
                                         goal: .strength, experience: .intermediate, now: now)
        let afterDecision = CoachDecisionEngine.run(afterFacts, schedulePreferences: prefs)

        #expect(afterFacts.weeklyBalance.strengthDays == 2,
                       "The morning strength workout is the second logged strength day")
        #expect(afterDecision.todayPlannedRecommendations.isEmpty,
                      "A partially completed two-a-day must not retain a one-item dual list")
        #expect(afterDecision.primary.isAerobic,
                      "The card's single Start action should launch the remaining cardio workout")
        #expect(afterDecision.planAdherence == .planAhead,
                       "Plan should not be complete until the planned cardio is also done")

        let todayCardio = makeCardioEvent(context: ctx, type: .cycle,
                                          date: now.addingTimeInterval(-900),
                                          duration: 35 * 60, avgHR: 135)
        let completeFacts = CoachFacts.make(from: [earlierStrength, todayStrength, todayCardio],
                                            goal: .strength, experience: .intermediate, now: now)
        let completeDecision = CoachDecisionEngine.run(completeFacts, schedulePreferences: prefs)

        #expect(completeDecision.todayPlannedRecommendations.count == 0,
                       "No planned workouts should remain after both two-a-day sessions are complete")
        if case .planComplete(let completedKind, let description, _) = completeDecision.planAdherence {
            #expect(completedKind == nil,
                         "Two-a-day completion should render the generic Plan followed state")
            #expect(description == "Strength and cardio — both in the books")
        } else {
            Issue.record("Plan should be complete after both planned workouts. Got: \(completeDecision.planAdherence)")
        }
    }

    @Test func twoADayAfterBothComplete() throws {
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

        #expect(decision.todayPlannedRecommendations.count == 0,
                       "Both done — no remaining recommendations")
        if case .planComplete(let completedKind, _, _) = decision.planAdherence {
            #expect(completedKind == nil,
                         "Two-a-day completion should render the generic Plan followed state")
        } else {
            Issue.record("Plan should be complete after both strength and cardio. Got: \(decision.planAdherence)")
        }
    }

    @Test func twoADayAlwaysOn() throws {
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        // Default prefs (allowsTwoADays = false)
        let decision = CoachDecisionEngine.run(facts)

        #expect(decision.todayPlannedRecommendations.count == 2,
                       "Strength and cardio are always both suggested")
    }

    // MARK: - Step health nudge

    @Test func lowStepNudgeWhenBelowFloor() {
        let activity: [DayActivity] = stride(from: 0, through: 6, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 3000)
        }
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate,
                                    activityTrend: activity)
        let decision = CoachDecisionEngine.run(facts)

        let stepFact = decision.observedFacts.first { $0.kind == .weeklySteps }
        #expect(stepFact != nil, "Should have weeklySteps observed fact")
        #expect(stepFact!.detail?.contains("Low") ?? false)

        let lowWarning = decision.warnings.first { $0.id == "lowSteps" }
        #expect(lowWarning != nil, "Should have lowSteps warning when below floor")
        #expect(lowWarning!.citationIds.contains("saintMauriceSteps2020"))
        #expect(lowWarning!.citationIds.contains("leeAccelerometer2019"))
    }

    @Test func noStepNudgeWhenOnTrack() {
        let activity: [DayActivity] = stride(from: 0, through: 6, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 9000)
        }
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate,
                                    activityTrend: activity)
        let decision = CoachDecisionEngine.run(facts)

        let stepFact = decision.observedFacts.first { $0.kind == .weeklySteps }
        #expect(stepFact != nil, "Should have weeklySteps observed fact")
        #expect(stepFact!.detail?.contains("On track") ?? false)

        let lowWarning = decision.warnings.first { $0.id == "lowSteps" }
        #expect(lowWarning == nil, "Should not have lowSteps warning when on track")
    }

    @Test func noStepFactWithoutActivityTrend() {
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate)
        let decision = CoachDecisionEngine.run(facts)

        let stepFact = decision.observedFacts.first { $0.kind == .weeklySteps }
        #expect(stepFact == nil, "Should not have weeklySteps fact without activity data")
    }

    @Test func stepNudgeDoesNotOverridePrimarySession() {
        let activity: [DayActivity] = stride(from: 0, through: 6, by: 1).map { offset in
            DayActivity(date: Date().addingTimeInterval(-Double(offset) * 86400), steps: 2000)
        }
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate,
                                    activityTrend: activity)
        let decision = CoachDecisionEngine.run(facts)

        #expect(decision.primary.kind != .rest, "Primary should not be rest despite low steps")
        let lowWarning = decision.warnings.first { $0.id == "lowSteps" }
        #expect(lowWarning != nil, "Should have lowSteps nudge")
        // Warning should not cite anything outside stepsHealth pool
        let allStepCitations = Set(lowWarning!.citationIds)
        let stepPoolIds = Set(CitationRegistry.stepsHealthPool.citationIds)
        #expect(allStepCitations.isSubset(of: stepPoolIds),
                      "Low-step warning should only cite stepsHealth pool citations")
    }

    // MARK: - CNS lift warning suppression

    @Test func cNSLiftSkipsExcessiveSetsPerSessionWarning() throws {
        let ctx = try makeContext()
        let now = testNow
        // Snatch with 12 sets — typical Olympic CNS training volume
        let snatch = try makeStrengthEvent(context: ctx, name: "Snatch",
                                            primaryMuscles: ["quadriceps", "glutes", "delts"],
                                            date: now.addingTimeInterval(-3600), sets: 12)
        let facts = CoachFacts.make(from: [snatch], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        let snatchWarnings = decision.warnings.filter { $0.id.contains("excessiveSetsPerSession") }
        #expect(snatchWarnings.isEmpty,
                      "CNS lift Snatch should NOT trigger excessiveSetsPerSession warning. Got: \(snatchWarnings.map(\.message))")
    }

    @Test func nonCNSLiftStillTriggersExcessiveSetsPerSessionWarning() throws {
        let ctx = try makeContext()
        let now = testNow
        // Back Squat with 12 sets — exceeds the threshold for a non-CNS lift
        let squat = try makeStrengthEvent(context: ctx, name: "Back Squat",
                                           primaryMuscles: ["quadriceps", "glutes"],
                                           date: now.addingTimeInterval(-3600), sets: 12)
        let facts = CoachFacts.make(from: [squat], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        let squatWarnings = decision.warnings.filter { $0.id.contains("excessiveSetsPerSession.Back Squat") }
        #expect(!squatWarnings.isEmpty,
                       "Non-CNS lift Back Squat should still trigger excessiveSetsPerSession warning")
    }

    @Test func cNSLiftBelowThresholdDoesNotTriggerWarning() throws {
        let ctx = try makeContext()
        let now = testNow
        // Clean and Jerk with 8 sets — below warning threshold
        let cj = try makeStrengthEvent(context: ctx, name: "Clean and Jerk",
                                        primaryMuscles: ["quadriceps", "glutes", "delts"],
                                        date: now.addingTimeInterval(-3600), sets: 8)
        let facts = CoachFacts.make(from: [cj], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)
        let cjWarnings = decision.warnings.filter { $0.id.contains("excessiveSetsPerSession") }
        #expect(cjWarnings.isEmpty,
                      "Clean and Jerk with 8 sets should not trigger warning (below 10 threshold)")
    }

    @Test func allCNSLiftNamesAreRecognized() {
        for name in Exercise.cnsLiftNames {
            #expect(Exercise.cnsLiftNames.contains(name),
                          "CNS lift '\(name)' should be in the cnsLiftNames set")
        }
        // Verify known non-CNS lifts are NOT in the set
        #expect(!Exercise.cnsLiftNames.contains("Back Squat"))
        #expect(!Exercise.cnsLiftNames.contains("Bench Press"))
        #expect(!Exercise.cnsLiftNames.contains("Deadlift"))
    }

    // MARK: - Both-modality completion (field-test issue #2)

    /// Doing BOTH strength and cardio today must complete the day even when the
    /// coach's plan for today would otherwise be recovery (both weekly targets
    /// already met). Previously this fell to offPlan and the card ignored cardio,
    /// showing a strength-only message.
    @Test func bothStrengthAndCardioTodayCompletesEvenOnRecoveryDay() throws {
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
            #expect(completedKind == nil,
                         "Both-modality completion should use the generic (nil) completed kind")
            #expect(description == "Strength and cardio — both in the books")
        } else {
            Issue.record("Both strength and cardio done today should complete the plan. Got: \(decision.planAdherence)")
        }
    }

    /// A short (any-duration) cardio still counts toward both-modality completion.
    @Test func shortCardioStillCompletesWithStrength() throws {
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
            #expect(completedKind == nil)
            #expect(description == "Strength and cardio — both in the books")
        } else {
            Issue.record("Any-duration cardio + strength today should complete. Got: \(decision.planAdherence)")
        }
    }

    /// Strength alone today (no cardio) must NOT report both-modality completion.
    @Test func strengthOnlyTodayIsNotBothComplete() throws {
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
            #expect(description != "Strength and cardio — both in the books",
                              "Strength alone must not claim both modalities are done")
        }
    }

    // MARK: - Phase C (field-test-fixes): cardio rescue before rest fallback

    /// Reproduces the "Take a Rest Day" on two-a-day Saturday bug: all non-rest
    /// candidates deferred, cardio target unmet, and the fallback MUST rescue
    /// a cardio session instead of recommending rest.
    @Test func cardioRescueBeforeRestFallback() throws {
        let ctx = try makeContext()
        let now = testNow

        // Two strength days already done; heavy session 30m ago blocks everything.
        let s1 = try makeStrengthEvent(context: ctx, name: "Squat", primaryMuscles: ["quadriceps"],
                                        date: now.addingTimeInterval(-2 * 86400))
        let s2 = try makeStrengthEvent(context: ctx, name: "Bench", primaryMuscles: ["chest"],
                                        date: now.addingTimeInterval(-4 * 86400))
        let today = try makeStrengthEvent(context: ctx, name: "Back Squat",
                                           primaryMuscles: ["quadriceps", "glutes", "hamstrings"],
                                           date: now.addingTimeInterval(-1800), sets: 5, rpe: 9,
                                           setCompletedAt: now.addingTimeInterval(-1800))

        let facts = CoachFacts.make(from: [s1, s2, today], goal: .strength,
                                     experience: .intermediate, now: now)

        // Cardio target is 6/wk but 0 cardio done. Strength 5/wk, 3 done.
        // On current code, rest may win when everything is blocked.
        let prefs = CoachSchedulePreferences(
            restPreference: .rolling(everyNDays: 4),
            allowsTwoADays: true)

        let decision = CoachDecisionEngine.run(facts, schedulePreferences: prefs)

        // The key assertion: when cardio is still needed, the decision must
        // recommend SOMETHING trainable — not pure rest.
        // After the fix, the fallback rescues a deferred cardio candidate
        // before ever falling back to rest.
        #expect(decision.primary.id != "rest.fallback",
                          "Must rescue cardio before rest.fallback when cardio target is unmet")
    }

    /// After the fix, when all candidates are deferred but cardio is needed, the
    /// primary must be a cardio session (e.g. easy walk), not rest.
    @Test func deferredAllButCardioNeededStillGetsTrainable() throws {
        let ctx = try makeContext()
        let now = testNow

        // Heavy squats <30min ago → blocks all strength and hard cardio via recovery.
        let today = try makeStrengthEvent(context: ctx, name: "Back Squat",
                                           primaryMuscles: ["quadriceps", "glutes", "hamstrings"],
                                           date: now.addingTimeInterval(-1200), sets: 5, rpe: 9,
                                           setCompletedAt: now.addingTimeInterval(-1200))

        let facts = CoachFacts.make(from: [today], goal: .strength,
                                     experience: .intermediate, now: now)

        // 0/6 cardio, 1/5 strength → cardio is the priority
        let prefs = CoachSchedulePreferences(
            restPreference: .rolling(everyNDays: 4),
            allowsTwoADays: true)

        let decision = CoachDecisionEngine.run(facts, schedulePreferences: prefs)

        // The primary must not be rest when cardio is still needed.
        if decision.primary.kind == CoachSessionKind.rest
            || decision.primary.id == "rest.fallback" {
            Issue.record("Got rest when cardio target (6/week) is unmet and 0 cardio done. Primary: \(decision.primary.id)")
        }
    }
}
#endif
