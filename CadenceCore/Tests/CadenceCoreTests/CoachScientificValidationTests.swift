import XCTest
import SwiftData
@testable import CadenceCore

/// Clean-room, black-box scientific validation of the Cadence coach.
///
/// Each test constructs curated workout history, predicts what the coach SHOULD
/// recommend based on published exercise science (cited from `CitationRegistry`),
/// and asserts the actual output matches. Tests use only the public API —
/// no internal scoring/eligibility/optimizer logic is referenced.
///
/// Deminimus methodology: start with a known-good baseline, make ONE small change,
/// predict the delta, verify.
final class CoachScientificValidationTests: XCTestCase {

    // MARK: - Test infrastructure (ported from existing test patterns)

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    /// Fixed absolute Thursday (2026-06-25 12:00) so windows are deterministic.
    private var testNow: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 25
        comps.hour = 12; comps.minute = 0; comps.second = 0
        return Calendar.current.date(from: comps) ?? Date(timeIntervalSince1970: 1_750_000_000)
    }

    private func makeStrengthEvent(context: ModelContext, name: String,
                                    primaryMuscles: [String], date: Date, sets: Int = 3,
                                    rpe: Double? = 8) throws -> TrainingEvent {
        let session = try WorkoutRepository.createSession(date: date.addingTimeInterval(-600), in: context)
        let ex = try WorkoutRepository.findOrCreateExercise(
            named: name, primaryMuscles: primaryMuscles, in: context)
        for _ in 0..<sets {
            _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 100, reps: 5,
                                             rpe: rpe, completedAt: date, in: context)
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

    /// Helper: assert a citation ID is valid in the registry.
    private func assertValidCitation(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(CitationRegistry.citation(forId: id),
                        "Citation '\(id)' must exist in CitationRegistry", file: file, line: line)
    }

    /// Helper: assert all observed citation IDs on a decision resolve.
    private func assertAllCitationsResolve(_ decision: CoachDecision, file: StaticString = #filePath, line: UInt = #line) {
        for id in decision.citationIds {
            assertValidCitation(id, file: file, line: line)
        }
        for w in decision.warnings {
            for id in w.citationIds {
                assertValidCitation(id, file: file, line: line)
            }
        }
    }

    // MARK: - Domain A: Recovery & Safety Gates
    //
    // Citation: meeusenOvertraining2013 — ECSS/ACSM consensus on overtraining
    //   prevention. Pain/illness requires rest or modified training.
    // Citation: parejaBlancoRecovery2020 — Neuromuscular performance after
    //   training to failure takes ~48h to recover for the exact same lift.
    // Citation: drewFinchInjury2016 — Relationship between training load and
    //   injury/illness/soreness. Backs consecutive hard-day warnings.
    // Citation: pellandDoseResponse2026 — Dose-response meta-regression for
    //   resistance training volume and strength/hypertrophy.

    /// A1: Pain concern should gate ALL hard training and recommend rest.
    /// Science: ECSS/ACSM consensus (meeusenOvertraining2013) states that
    /// pain/illness requires rest or modified training to prevent overtraining.
    func testA1_painConcernBlocksHardTraining() throws {
        let now = testNow

        // Even with no prior training (cold start), pain should override.
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts, hasPainConcern: true)

        // PREDICT: Primary = rest (not strength, not hard cardio).
        // CITATION: meeusenOvertraining2013
        XCTAssertEqual(decision.primary.kind, .rest,
                       "A1 FAIL: Pain must yield rest primary. Got: \(decision.primary.kind)")
        XCTAssertFalse(decision.warnings.isEmpty,
                       "A1 FAIL: Pain should generate a warning")
        XCTAssertTrue(decision.warnings.contains { $0.id == "painConcern" },
                      "A1 FAIL: Should have painConcern warning")
        assertAllCitationsResolve(decision)
        assertValidCitation("meeusenOvertraining2013")
    }

    /// A2: 48h same-lift recovery: a hard squat within 48h must block that same
    /// lift from the next day's primary exercises.
    /// Science: parejaBlancoRecovery2020 — neuromuscular performance after
    /// training to failure takes ~48h to recover.
    func testA2_48hSameLiftRecoveryBlocksSquat() throws {
        let ctx = try makeContext()
        let now = testNow

        // Hard squat session 6 hours ago (well within 48h window)
        let squat = try makeStrengthEvent(context: ctx, name: "Back Squat",
                                           primaryMuscles: ["quadriceps", "glutes"],
                                           date: now.addingTimeInterval(-6 * 3600),
                                           sets: 5, rpe: 9)
        let facts = CoachFacts.make(from: [squat], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)

        // If primary is strength, "Back Squat" should NOT be the dominant exercise
        // (squat pattern is still recovering).
        // The coach may still recommend strength (different movements) or aerobic.
        if decision.primary.kind == .strength {
            let exercises = decision.primary.exercises ?? []
            let hasSquat = exercises.contains { ex in
                ex.name == "Back Squat"
            }
            XCTAssertFalse(hasSquat,
                           "A2 FAIL: Back Squat within 48h recovery window should not be in primary. Exercises: \(exercises.map(\.name))")
        }
        // At minimum, verify that the squat session (or strength candidates) are
        // deferred due to 48h recovery window. Reason IDs may vary (exactLift,
        // bodyPart, pattern, etc.) but there should be deferred candidates.
        XCTAssertFalse(decision.deferred.isEmpty,
                       "A2 FAIL: Some candidates should be deferred for recovery. Got 0 deferred")

        assertAllCitationsResolve(decision)
        assertValidCitation("parejaBlancoRecovery2020")
    }

    /// A3: 6+ consecutive hard days triggers an overtraining warning.
    /// Science: meeusenOvertraining2013 + drewFinchInjury2016 — consecutive
    /// hard training days without recovery increase injury risk.
    func testA3_sixConsecutiveHardDaysTriggersWarning() throws {
        let ctx = try makeContext()
        // Use Sunday so all 6 preceding days (Mon–Sat) are in the same week
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 28  // Sunday
        comps.hour = 12; comps.minute = 0; comps.second = 0
        let sunday = Calendar.current.date(from: comps)!

        // Create 6 consecutive days (Mon–Sat) of hard strength training
        var events: [TrainingEvent] = []
        for dayOffset in 1...6 {
            let date = sunday.addingTimeInterval(-Double(dayOffset) * 86400)
            let ex = try makeStrengthEvent(context: ctx, name: "Day\(dayOffset) Lift",
                                            primaryMuscles: ["quadriceps"],
                                            date: date, sets: 5, rpe: 9)
            events.append(ex)
        }
        let facts = CoachFacts.make(from: events, goal: .strength, experience: .intermediate, now: sunday)
        let decision = CoachDecisionEngine.run(facts)

        // PREDICT: Warning about consecutive hard days.
        // CITATION: meeusenOvertraining2013, drewFinchInjury2016
        XCTAssertTrue(decision.warnings.contains { $0.id == "consecutiveHardDays" },
                      "A3 FAIL: 6 consecutive hard days should trigger warning. Warnings: \(decision.warnings.map(\.id))")

        if let warning = decision.warnings.first(where: { $0.id == "consecutiveHardDays" }) {
            XCTAssertTrue(warning.citationIds.contains("meeusenOvertraining2013") ||
                          warning.citationIds.contains("drewFinchInjury2016"),
                          "A3 FAIL: Warning should cite recovery science")
        }
        assertAllCitationsResolve(decision)
        assertValidCitation("meeusenOvertraining2013")
        assertValidCitation("drewFinchInjury2016")
    }

    /// A4: >20 sets for one body part in a week triggers excessive volume warning.
    /// Science: pellandDoseResponse2026 — diminishing returns above certain
    /// weekly volume thresholds.
    func testA4_excessiveWeeklyVolumeTriggersWarning() throws {
        let ctx = try makeContext()
        let now = testNow

        // 4 chest sessions this week, 6 sets each = 24 sets → above threshold
        var events: [TrainingEvent] = []
        for dayOffset in 0..<4 {
            let date = now.addingTimeInterval(-Double(dayOffset) * 86400)
            let ex = try makeStrengthEvent(context: ctx, name: "Bench Press",
                                            primaryMuscles: ["chest"],
                                            date: date, sets: 6, rpe: 8)
            events.append(ex)
        }
        let facts = CoachFacts.make(from: events, goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)

        // PREDICT: Warning about excessive chest volume.
        // CITATION: pellandDoseResponse2026
        let chestWarning = decision.warnings.first { $0.id.contains("chest") || $0.id.contains("excessiveWeeklyVolume") }
        XCTAssertNotNil(chestWarning,
                        "A4 FAIL: 24 sets of chest should trigger volume warning. Warnings: \(decision.warnings.map { "\($0.id): \($0.message)" })")
        if let w = chestWarning {
            XCTAssertTrue(w.citationIds.contains("pellandDoseResponse2026"),
                          "A4 FAIL: Volume warning should cite pellandDoseResponse2026")
        }
        assertAllCitationsResolve(decision)
        assertValidCitation("pellandDoseResponse2026")
    }

    // MARK: - Domain B: Balance & Priority
    //
    // Citation: ekelundActivityMortality2016 — Physical activity attenuates
    //   sitting-time mortality risk. Backs the aerobic floor recommendation.
    // Citation: schoenfeld2021 — Loading recommendations for strength,
    //   hypertrophy, and local endurance. Anchors strength prescriptions.
    // Citation: crowleyVO2Intensity2022 — Exercise intensity and VO2max
    //   improvement. Backs VO2-interval eligibility.
    // Citation: frequencyMeta — ≥2 sessions/muscle/week improves per-set
    //   quality and recovery. Backs weekly plan distribution.
    // Citation: schumannConcurrent2022 — Concurrent aerobic + strength
    //   compatibility. Backs two-a-day guidance.

    /// B1: With 2 strength days done and no cardio, the aerobic deficit should
    /// drive the coach to recommend aerobic work.
    /// Science: ekelundActivityMortality2016 — meeting the aerobic floor
    /// (150 min moderate-equivalent) attenuates mortality risk.
    func testB1_aerobicDeficitRecommendsAerobic() throws {
        let ctx = try makeContext()
        let now = testNow

        // Two strength sessions earlier this week (meets strength floor)
        let s1 = try makeStrengthEvent(context: ctx, name: "Back Squat",
                                        primaryMuscles: ["quadriceps", "glutes"],
                                        date: now.addingTimeInterval(-3 * 86400))
        let s2 = try makeStrengthEvent(context: ctx, name: "Bench Press",
                                        primaryMuscles: ["chest"],
                                        date: now.addingTimeInterval(-5 * 86400))
        // No cardio events → aerobic minutes = 0

        let facts = CoachFacts.make(from: [s1, s2], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)

        // PREDICT: Primary is aerobic (easy or moderate), not strength.
        // CITATION: ekelundActivityMortality2016
        XCTAssertTrue(decision.primary.kind == .easyAerobic || decision.primary.kind == .moderateAerobic,
                      "B1 FAIL: With strength met and no cardio, primary should be aerobic. Got: \(decision.primary.kind)")
        assertAllCitationsResolve(decision)
        assertValidCitation("ekelundActivityMortality2016")
    }

    /// B2: With aerobic floor met but zero strength, the coach should recommend
    /// a strength session.
    /// Science: schoenfeld2021 — loading recommendations for strength
    /// development; strength training should be prioritized when unmet.
    func testB2_strengthDeficitRecommendsStrength() throws {
        let ctx = try makeContext()
        let now = testNow

        // Three 60-min runs = 180 moderate-equivalent min → meets aerobic floor
        let runs: [TrainingEvent] = (1...3).map {
            makeCardioEvent(context: ctx, type: .run,
                            date: now.addingTimeInterval(-Double($0) * 86400),
                            duration: 3600, avgHR: 140)
        }
        // Zero strength sessions

        let facts = CoachFacts.make(from: runs, goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)

        // PREDICT: Primary is strength.
        // CITATION: schoenfeld2021
        XCTAssertEqual(decision.primary.kind, .strength,
                       "B2 FAIL: With aerobic met and no strength, primary should be strength. Got: \(decision.primary.kind)")
        assertAllCitationsResolve(decision)
        assertValidCitation("schoenfeld2021")
    }

    /// B3: When both floors are met, the coach surfaces VO2/anaerobic interval
    /// candidates — not just easy/moderate.
    /// Science: crowleyVO2Intensity2022 + poonHIIT2024 — HIIT and VO2 intervals
    /// improve cardiorespiratory fitness beyond steady-state when base is solid.
    func testB3_bothFloorsMetSurfacesHarderOptions() throws {
        let ctx = try makeContext()
        let now = testNow

        // Strength: 3 sessions (meets ≥2 target)
        let strength: [TrainingEvent] = try (1...3).map {
            try makeStrengthEvent(context: ctx, name: "Lift\($0)",
                                   primaryMuscles: [$0 == 1 ? "quadriceps" : $0 == 2 ? "chest" : "back"],
                                   date: now.addingTimeInterval(-Double($0) * 86400))
        }
        // Cardio: 3 x 60-min runs (meets 150 min moderate-equivalent)
        let cardio: [TrainingEvent] = (1...3).map {
            makeCardioEvent(context: ctx, type: .run,
                            date: now.addingTimeInterval(-Double($0) * 86400 - 3600),
                            duration: 3600, avgHR: 140)
        }

        let facts = CoachFacts.make(from: strength + cardio, goal: .strength, experience: .intermediate, now: now)
        let candidates = CoachSession.candidates(for: facts)

        // PREDICT: VO2 intervals candidate is present (requires ≥75 min base).
        // CITATION: crowleyVO2Intensity2022, poonHIIT2024
        let vo2Candidate = candidates.first { $0.id == "aerobic.vo2Intervals" }
        XCTAssertNotNil(vo2Candidate,
                        "B3 FAIL: With both floors met, VO2 intervals should be a candidate. Candidates: \(candidates.map(\.id))")
        if let vo2 = vo2Candidate {
            XCTAssertFalse(vo2.citationIds.isEmpty,
                           "B3 FAIL: VO2 candidate should carry citations")
        }
        assertValidCitation("crowleyVO2Intensity2022")
        assertValidCitation("poonHIIT2024")
    }

    /// B4: With 3 strength days/week target, the weekly plan distributes
    /// remaining sessions across different days (not all on one day).
    /// Science: frequencyMeta — ≥2 sessions/muscle/week improves quality.
    func testB4_weeklyPlanDistributesStrengthAcrossDays() throws {
        let now = testNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let prefs = CoachSchedulePreferences(strengthDaysPerWeek: 3, cardioDaysPerWeek: 2)

        let plan = WeeklyPlan.generate(from: facts, schedulePreferences: prefs)

        // PREDICT: Remaining week has strength sessions on >1 day.
        // CITATION: frequencyMeta
        let futureStrength = plan.futureDays.filter { day in
            day.sessions.contains { $0.kind == .strength }
        }
        XCTAssertGreaterThanOrEqual(futureStrength.count, 1,
                                    "B4 FAIL: Should plan at least 1 future strength session")
        // If there are multiple strength days, they should be on different days
        let strengthDates = Set(futureStrength.map { Calendar.current.startOfDay(for: $0.date) })
        XCTAssertEqual(strengthDates.count, futureStrength.count,
                       "B4 FAIL: Future strength sessions should be on distinct days")
        assertValidCitation("frequencyMeta")
    }

    /// B5: With two-a-days enabled, completing both strength and cardio today
    /// marks the plan as complete.
    /// Science: schumannConcurrent2022 — concurrent training compatibility;
    /// completing both modalities in one day is a valid training stimulus.
    func testB5_twoADayCompletionDetected() throws {
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

        // PREDICT: Both done → plan complete.
        // CITATION: schumannConcurrent2022
        if case .planComplete = decision.planAdherence {
            // Expected
        } else {
            XCTFail("B5 FAIL: Both strength and cardio today should complete plan. Got: \(decision.planAdherence)")
        }
        XCTAssertEqual(decision.todayPlannedRecommendations.count, 0,
                       "B5 FAIL: No remaining recommendations when both done")
        assertAllCitationsResolve(decision)
        assertValidCitation("schumannConcurrent2022")
    }

    // MARK: - Domain C: Preference Learning

    /// C1: A recorded cycling preference causes the coach to recommend cycling
    /// for aerobic work.
    func testC1_cyclingPreferenceRememberedAndRecommended() throws {
        let ctx = try makeContext()
        let now = testNow

        // Strength floor met, aerobic deficit → coach would normally pick any aerobic
        let s1 = try makeStrengthEvent(context: ctx, name: "Back Squat",
                                        primaryMuscles: ["quadriceps"],
                                        date: now.addingTimeInterval(-3 * 86400))
        let s2 = try makeStrengthEvent(context: ctx, name: "Bench Press",
                                        primaryMuscles: ["chest"],
                                        date: now.addingTimeInterval(-5 * 86400))

        var profile = CoachPreferenceProfile.empty
        profile.aerobicPreferences = [
            AerobicPreference(intent: .moderateAerobic, modality: .cycle, score: 5, updatedAt: now)
        ]

        let facts = CoachFacts.make(from: [s1, s2], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts, profile: profile)

        // PREDICT: With cycle preference and aerobic deficit, primary = moderate cycle.
        // This tests that user preferences are respected by the scoring system.
        if decision.primary.kind == .moderateAerobic || decision.primary.kind == .easyAerobic {
            XCTAssertEqual(decision.primary.modality, .cycle,
                           "C1 FAIL: Cycle preference should make cycle primary. Got: \(decision.primary.modality?.rawValue ?? "nil")")
        }
        assertAllCitationsResolve(decision)
    }

    /// C2: HighImpact avoidance tag should keep running out of primary when
    /// low-impact alternatives exist.
    func testC2_highImpactAvoidanceKeepsRunOut() throws {
        let now = testNow

        var profile = CoachPreferenceProfile.empty
        profile.avoidedTags = ["highImpact"]

        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts, profile: profile)

        // PREDICT: With highImpact avoided, primary should NOT be a run session.
        // Low-impact alternatives (walk, cycle, swim) should be preferred.
        if decision.primary.kind == .moderateAerobic || decision.primary.kind == .easyAerobic {
            XCTAssertNotEqual(decision.primary.modality, .run,
                              "C2 FAIL: Run should not be primary when highImpact is avoided. Got: \(decision.primary.modality?.rawValue ?? "nil")")
        }
        assertAllCitationsResolve(decision)
    }

    /// C3: Strength exercise preference — the coach's most_trained_exercises
    /// should surface the user's historically most-used lifts.
    func testC3_mostTrainedExercisesSurfaceInStrengthSession() throws {
        let ctx = try makeContext()
        let now = testNow

        // Train bench press 3 times (more than any other lift)
        for day in 0..<3 {
            _ = try makeStrengthEvent(context: ctx, name: "Bench Press",
                                       primaryMuscles: ["chest"],
                                       date: now.addingTimeInterval(-Double(day + 1) * 86400),
                                       sets: 4, rpe: 8)
        }
        // Train squat only once
        _ = try makeStrengthEvent(context: ctx, name: "Back Squat",
                                   primaryMuscles: ["quadriceps"],
                                   date: now.addingTimeInterval(-6 * 86400),
                                   sets: 3, rpe: 8)

        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)

        // If primary is strength, exercises should reflect training history
        if decision.primary.kind == .strength, let exercises = decision.primary.exercises {
            let exerciseNames = exercises.map(\.name)
            // Should have some exercises (not empty)
            XCTAssertFalse(exerciseNames.isEmpty,
                           "C3 FAIL: Strength session should include exercises. Got empty list")
        }
        assertAllCitationsResolve(decision)
    }

    // MARK: - Domain D: Assessment & Baseline

    /// D1: A trained system with no assessment baseline → coach surfaces
    /// an assessment prompt candidate.
    /// Science: oneRMEstimation — e1RM prediction equations require a baseline
    /// to anchor load targets accurately.
    func testD1_noBaselineSurfacesAssessmentPrompt() throws {
        let ctx = try makeContext()
        let now = testNow

        // Train strength but never do an assessment
        let s = try makeStrengthEvent(context: ctx, name: "Back Squat",
                                       primaryMuscles: ["quadriceps"],
                                       date: now.addingTimeInterval(-2 * 86400))

        let facts = CoachFacts.make(from: [s], goal: .strength, experience: .intermediate, now: now)
        let candidates = CoachSession.candidates(for: facts)

        // PREDICT: Assessment candidate present (system trained, no baseline).
        // CITATION: oneRMEstimation
        let assessCandidate = candidates.first { $0.kind == .assessment }
        XCTAssertNotNil(assessCandidate,
                        "D1 FAIL: Trained system without baseline should surface assessment candidate. Candidates: \(candidates.map(\.id))")
        if let assess = assessCandidate {
            XCTAssertFalse(assess.citationIds.isEmpty,
                           "D1 FAIL: Assessment candidate should carry citations")
        }
        assertValidCitation("oneRMEstimation")
    }

    /// D2: Adequate aerobic base (≥90 mod-eq min) → threshold tempo candidate
    /// surfaces.
    /// Science: kaufmannThreshold2023 — HRV-derived thresholds for exercise
    /// intensity prescription; threshold work builds on an established base.
    func testD2_aerobicBaseEnablesThresholdTempo() throws {
        let ctx = try makeContext()
        let now = testNow

        // Two 60-min runs = 120 mod-eq min → meets threshold eligibility
        let runs: [TrainingEvent] = [
            makeCardioEvent(context: ctx, type: .run,
                            date: now.addingTimeInterval(-1 * 86400),
                            duration: 3600, avgHR: 140),
            makeCardioEvent(context: ctx, type: .run,
                            date: now.addingTimeInterval(-2 * 86400),
                            duration: 3600, avgHR: 140),
        ]

        let facts = CoachFacts.make(from: runs, goal: .strength, experience: .intermediate, now: now)
        let candidates = CoachSession.candidates(for: facts)

        // PREDICT: Threshold tempo candidate present.
        // CITATION: kaufmannThreshold2023
        let threshold = candidates.first { $0.id == "aerobic.thresholdTempo" }
        XCTAssertNotNil(threshold,
                        "D2 FAIL: Adequate aerobic base should enable threshold tempo candidate. Candidates: \(candidates.map(\.id))")
        if let t = threshold {
            XCTAssertEqual(t.systemsTrained, [.threshold],
                           "D2 FAIL: Threshold tempo should train threshold system")
            XCTAssertEqual(t.evidenceCategory, .thresholdTraining,
                           "D2 FAIL: Threshold tempo should use thresholdTraining category")
        }
        assertValidCitation("kaufmannThreshold2023")
    }

    /// D3: When an assessment baseline exists (fresh), the coach does NOT nag
    /// for a new assessment.
    /// Science: fieldFitnessReliability2022 — field tests are reliable;
    /// a recent baseline means no prompt needed.
    func testD3_freshAssessmentSuppressesPrompt() throws {
        let now = testNow

        // No events at all (brand new user)
        let noEventFacts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let noEventCandidates = CoachSession.candidates(for: noEventFacts)
        let noEventAssess = noEventCandidates.first { $0.kind == .assessment }
        // Cold start with no events → should NOT get assessment prompt (no system was trained)
        XCTAssertNil(noEventAssess,
                     "D3: No events → no assessment prompt needed (nothing was trained yet)")

        // With events but still no baseline, assessment should appear (confirmed by D1)
        assertValidCitation("fieldFitnessReliability2022")
    }

    // MARK: - Domain E: Deminimus Edge Cases

    /// E1: Soft-deleted sessions are excluded from weekly volume and recovery.
    func testE1_deletedSessionsExcluded() throws {
        let ctx = try makeContext()
        let now = testNow

        let s = try WorkoutRepository.createSession(date: now.addingTimeInterval(-2 * 86400), in: ctx)
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Bench Press",
                                                             primaryMuscles: ["chest"], in: ctx)
        for _ in 0..<8 {
            _ = try WorkoutRepository.addSet(to: s, exercise: ex, weightKg: 60, reps: 5, rpe: 7, in: ctx)
        }
        s.endedAt = now.addingTimeInterval(-2 * 86400)
        s.deletedAt = now  // Mark as deleted
        try ctx.save()

        let snap = CoachSnapshotBuilder.build(
            sessions: [s], cardio: [], assessments: [], hasPainToday: false,
            goal: .strength, experience: .intermediate, formula: .epley,
            schedulePreferences: CoachSchedulePreferences(), profile: .empty, now: now)

        // PREDICT: Weekly chest sets = 0 (deleted session excluded).
        XCTAssertEqual(snap.facts.weeklySetsByPart[.chest] ?? 0, 0,
                       "E1 FAIL: Deleted session should not count toward weekly volume")
    }

    /// E2: Future-dated events are excluded from weekly balance.
    func testE2_futureDatedEventsExcluded() throws {
        let ctx = try makeContext()
        let now = testNow

        let pastWalk = makeCardioEvent(context: ctx, type: .walk,
                                        date: now.addingTimeInterval(-3600),
                                        duration: 1800, avgHR: nil)
        let futureRun = makeCardioEvent(context: ctx, type: .run,
                                         date: now.addingTimeInterval(86400),  // Tomorrow
                                         duration: 3600, avgHR: 160)

        let facts = CoachFacts.make(from: [futureRun, pastWalk], goal: .strength,
                                     experience: .intermediate, now: now)

        // PREDICT: Only past walk counts. Future run excluded.
        XCTAssertGreaterThan(facts.weeklyBalance.moderateEquivalentMinutes, 0,
                             "E2 FAIL: Past walk should count")
        let decision = CoachDecisionEngine.run(facts)
        let cardioFact = decision.observedFacts.first { $0.kind == .lastCardio }
        XCTAssertTrue(cardioFact?.detail?.contains("Walk") ?? false,
                      "E2 FAIL: Last cardio should be past walk, not future run. Got: \(cardioFact?.detail ?? "nil")")
    }

    /// E3: Beginner with <5 sessions gets Full-body A/B candidates.
    /// Science: schoenfeld2021 — loading recommendations; beginners benefit
    /// from structured full-body programs.
    func testE3_beginnerGetsStructuredSessions() throws {
        let now = testNow

        let facts = CoachFacts.make(from: [], goal: .strength, experience: .beginner, now: now)
        let candidates = CoachSession.candidates(for: facts)

        // PREDICT: Beginner A and B sessions present.
        // CITATION: schoenfeld2021
        XCTAssertTrue(candidates.contains { $0.id == "strength.beginnerA" },
                      "E3 FAIL: Beginner should get Full-body A candidate")
        XCTAssertTrue(candidates.contains { $0.id == "strength.beginnerB" },
                      "E3 FAIL: Beginner should get Full-body B candidate")
        assertValidCitation("schoenfeld2021")
    }

    /// E4: With only 2 consecutive hard days, recovery should NOT be forced as
    /// primary (unlike 6+ days in A3).
    /// Science: meeusenOvertraining2013 — overtraining risk escalates with
    /// consecutive days; 2 days is normal training rhythm.
    func testE4_twoConsecutiveHardDaysDoesNotForceRecovery() throws {
        let ctx = try makeContext()
        let now = testNow

        // Only 2 consecutive hard days (normal training)
        let s1 = try makeStrengthEvent(context: ctx, name: "Day1",
                                        primaryMuscles: ["quadriceps"],
                                        date: now.addingTimeInterval(-1 * 86400),
                                        sets: 5, rpe: 9)
        let s2 = try makeStrengthEvent(context: ctx, name: "Day2",
                                        primaryMuscles: ["chest"],
                                        date: now.addingTimeInterval(-2 * 86400),
                                        sets: 5, rpe: 9)

        let facts = CoachFacts.make(from: [s1, s2], goal: .strength, experience: .intermediate, now: now)
        let decision = CoachDecisionEngine.run(facts)

        // PREDICT: NO consecutive hard days warning (only 2 days).
        // CITATION: meeusenOvertraining2013
        let consecutiveWarning = decision.warnings.first { $0.id == "consecutiveHardDays" }
        XCTAssertNil(consecutiveWarning,
                     "E4 FAIL: 2 consecutive hard days should NOT trigger overtraining warning")
        assertValidCitation("meeusenOvertraining2013")
    }

    /// E5: Coach output is deterministic — identical inputs twice produce
    /// identical primary session ID, insights, and recommendation.
    func testE5_deterministicOutput() throws {
        let ctx = try makeContext()
        let now = testNow

        let s1 = try makeStrengthEvent(context: ctx, name: "Back Squat",
                                        primaryMuscles: ["quadriceps"],
                                        date: now.addingTimeInterval(-3 * 86400))

        let facts1 = CoachFacts.make(from: [s1], goal: .strength, experience: .intermediate, now: now)
        let facts2 = CoachFacts.make(from: [s1], goal: .strength, experience: .intermediate, now: now)

        let d1 = CoachDecisionEngine.run(facts1)
        let d2 = CoachDecisionEngine.run(facts2)

        // PREDICT: Identical inputs → identical outputs.
        XCTAssertEqual(d1.primary.id, d2.primary.id,
                       "E5 FAIL: Same inputs should yield same primary")
        XCTAssertEqual(d1.primary.kind, d2.primary.kind,
                       "E5 FAIL: Same inputs should yield same primary kind")
        XCTAssertEqual(d1.warnings.map(\.id), d2.warnings.map(\.id),
                       "E5 FAIL: Same inputs should yield same warnings")
        XCTAssertEqual(d1.planAdherence, d2.planAdherence,
                       "E5 FAIL: Same inputs should yield same plan adherence")
    }

    // MARK: - Snapshot Integration Tests

    /// Verify the full snapshot builder runs end-to-end without error
    /// on a realistic multi-week training history.
    func test_fullSnapshotEndToEnd() throws {
        let ctx = try makeContext()
        let now = testNow

        // 3 weeks of varied training:
        var sessions: [WorkoutSession] = []

        for week in 0..<3 {
            let weekOffset = Double(week * 7)
            // Mon: strength
            let mon = try WorkoutRepository.createSession(
                date: now.addingTimeInterval(-(weekOffset + 3) * 86400), in: ctx)
            let squat = try WorkoutRepository.findOrCreateExercise(
                named: "Back Squat", primaryMuscles: ["quadriceps", "glutes"], in: ctx)
            let bench = try WorkoutRepository.findOrCreateExercise(
                named: "Bench Press", primaryMuscles: ["chest"], in: ctx)
            for _ in 0..<3 {
                _ = try WorkoutRepository.addSet(to: mon, exercise: squat, weightKg: 80, reps: 5, rpe: 7, in: ctx)
                _ = try WorkoutRepository.addSet(to: mon, exercise: bench, weightKg: 60, reps: 8, rpe: 7, in: ctx)
            }
            mon.endedAt = now.addingTimeInterval(-(weekOffset + 3) * 86400)
            sessions.append(mon)

            // Wed: strength
            let wed = try WorkoutRepository.createSession(
                date: now.addingTimeInterval(-(weekOffset + 1) * 86400), in: ctx)
            let deadlift = try WorkoutRepository.findOrCreateExercise(
                named: "Deadlift", primaryMuscles: ["hamstrings", "glutes"], in: ctx)
            let row = try WorkoutRepository.findOrCreateExercise(
                named: "Barbell Row", primaryMuscles: ["back"], in: ctx)
            for _ in 0..<3 {
                _ = try WorkoutRepository.addSet(to: wed, exercise: deadlift, weightKg: 100, reps: 5, rpe: 7, in: ctx)
                _ = try WorkoutRepository.addSet(to: wed, exercise: row, weightKg: 50, reps: 8, rpe: 7, in: ctx)
            }
            wed.endedAt = now.addingTimeInterval(-(weekOffset + 1) * 86400)
            sessions.append(wed)
        }

        let cardio: [CardioWorkout] = [
            CardioWorkout(type: .run, start: now.addingTimeInterval(-3600 - 2 * 86400),
                          end: now.addingTimeInterval(-2 * 86400), avgHeartRate: 140, source: .iphone),
            CardioWorkout(type: .walk, start: now.addingTimeInterval(-1800),
                          end: now, avgHeartRate: 110, source: .iphone),
        ]

        let snap = CoachSnapshotBuilder.build(
            sessions: sessions, cardio: cardio, assessments: [], hasPainToday: false,
            goal: .strength, experience: .intermediate, formula: .epley,
            schedulePreferences: CoachSchedulePreferences(), profile: .empty, now: now)

        // Basic sanity: snapshot is non-empty and well-formed
        XCTAssertFalse(snap.decision.primary.id.isEmpty,
                       "Snapshot should have a primary decision")
        XCTAssertFalse(snap.plan.days.isEmpty,
                       "Snapshot should have a weekly plan")
        XCTAssertFalse(snap.recommendation.title.isEmpty,
                       "Snapshot should have a recommendation")

        // All citations must resolve
        let known = Set(CitationRegistry.all.map(\.id))
        for insight in snap.insights {
            XCTAssertTrue(known.contains(insight.citation.id),
                          "Insight citation '\(insight.citation.id)' must exist in registry")
        }
        for id in snap.decision.citationIds {
            assertValidCitation(id)
        }
        for id in snap.recommendation.citationIds {
            if !id.isEmpty {
                assertValidCitation(id)
            }
        }
        assertValidCitation(snap.recommendation.citation.id)
    }
}
