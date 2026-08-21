import XCTest
import SwiftData
@testable import CadenceCore

/// strength-pivot P5.1 — the prescriptive inference engine over `TrainingFacts`.
final class RecommendationEngineTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    /// Build a synthetic facts snapshot directly (bypassing the store) for
    /// table-driven rule tests, mirroring how `TrainingFacts.make` would fill it.
    private func facts(snapshots: [LiftSnapshot] = [],
                       weeklySets: [BodyPart: Double] = [:],
                       goal: TrainingGoal = .strength,
                       experience: ExperienceLevel = .intermediate) -> TrainingFacts {
        TrainingFacts(
            weeklySetsByPart: weeklySets,
            frequencyByPart: [:],
            e1RMTrendByExercise: [:],
            intensity: .empty,
            avgRPE: nil,
            daysSinceLastSession: nil,
            totalWorkingSets: snapshots.isEmpty && weeklySets.isEmpty ? 0 : 1,
            liftSnapshots: Dictionary(uniqueKeysWithValues: snapshots.map { ($0.exercise, $0) }),
            goal: goal,
            experience: experience)
    }

    private func snapshot(_ name: String, weight: Double, reps: Int,
                          trend: TrendDirection?, part: BodyPart? = .legs) -> LiftSnapshot {
        LiftSnapshot(exercise: name, part: part, topSetWeightKg: weight,
                     topSetReps: reps, bestE1RM: weight, trend: trend)
    }

    // MARK: cold-start

    func testColdStartReturnsStarter() {
        let recs = RecommendationEngine.run(facts())
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs.first?.kind, .starter)
        XCTAssertNotNil(recs.first?.target)
        XCTAssertEqual(RecommendationEngine.top(facts()).kind, .starter)
    }

    func testStarterUsesGoalRepRangeAndRIR() {
        let starter = KnowledgeBase.starter(goal: .hypertrophy, experience: .intermediate)
        XCTAssertEqual(starter.target?.repsLow, 6)
        XCTAssertEqual(starter.target?.repsHigh, 12)
        XCTAssertEqual(starter.target?.rir, 1)
        XCTAssertEqual(starter.target?.sets, 3)
    }

    // MARK: progression (double progression)

    func testAddsRepWhenBelowTopOfRange() {
        // strength range 3–5; 4 reps → aim for 5 at the same load.
        let f = facts(snapshots: [snapshot("Squat", weight: 100, reps: 4, trend: .flat)], goal: .strength)
        let rec = RecommendationEngine.run(f).first { $0.id == "progression.Squat" }
        XCTAssertEqual(rec?.target?.repsLow, 5)
        XCTAssertEqual(rec?.target?.repsHigh, 5)
        XCTAssertEqual(rec?.target?.loadKg, 100)        // same load
        XCTAssertEqual(rec?.target?.rir, 2)
        XCTAssertEqual(rec?.confidence, .high)          // flat = clear plateau cue
    }

    func testAddsLoadAtTopOfRange() {
        // strength range 3–5; already at 5 reps → add 2.5 kg, reset to 3 reps.
        let f = facts(snapshots: [snapshot("Squat", weight: 100, reps: 5, trend: .rising)], goal: .strength)
        let rec = RecommendationEngine.run(f).first { $0.id == "progression.Squat" }
        XCTAssertEqual(rec?.target?.loadKg, 102.5)
        XCTAssertEqual(rec?.target?.repsLow, 3)         // reset to bottom
        XCTAssertEqual(rec?.confidence, .moderate)      // rising = keep going
    }

    // MARK: deload

    func testDecliningLiftGetsDeloadNotProgression() {
        let f = facts(snapshots: [snapshot("Squat", weight: 100, reps: 5, trend: .declining)], goal: .strength)
        let recs = RecommendationEngine.run(f)
        XCTAssertNil(recs.first { $0.id == "progression.Squat" })
        let deload = recs.first { $0.id == "deload.Squat" }
        XCTAssertEqual(deload?.kind, .deload)
        XCTAssertEqual(deload?.target?.loadKg, 90)      // ~10% off, rounded to 2.5
        XCTAssertEqual(deload?.target?.rir, 3)          // more in reserve
        XCTAssertEqual(deload?.citation.id, CitationRegistry.rpeAutoregulation.id)
    }

    func testDeloadDoesNotOutrankProgression() {
        let f = facts(snapshots: [
            snapshot("Bench", weight: 80, reps: 4, trend: .flat),       // → progression (pri 100)
            snapshot("Squat", weight: 100, reps: 5, trend: .declining), // → deload (pri 95, now below progression)
        ], goal: .strength)
        // Progression now outranks deload — single-week decline is monitored, not blocked.
        XCTAssertEqual(RecommendationEngine.run(f).first?.id, "progression.Bench")
    }

    // MARK: add volume

    func testAddVolumeBelowMEV() {
        // 2 sets/week is below the minimum effective volume for any part.
        let f = facts(weeklySets: [.chest: 2], goal: .hypertrophy)
        let rec = RecommendationEngine.run(f).first { $0.id == "addVolume.chest" }
        XCTAssertEqual(rec?.kind, .addVolume)
        XCTAssertEqual(rec?.part, .chest)
        XCTAssertNil(rec?.target?.loadKg)               // volume, not a specific load
        XCTAssertGreaterThanOrEqual(rec?.target?.sets ?? 0, 1)
        XCTAssertEqual(rec?.citation.id, CitationRegistry.volumeDoseResponse.id)
    }

    func testProductiveVolumeProducesNoAddVolume() {
        // A large weekly volume is well above MEV → no add-volume recommendation.
        let f = facts(weeklySets: [.chest: 40], goal: .hypertrophy)
        XCTAssertNil(RecommendationEngine.run(f).first { $0.id == "addVolume.chest" })
    }

    // MARK: invariants

    func testEveryRecommendationIsCited() {
        let known = Set(CitationRegistry.all.map(\.id))
        let f = facts(snapshots: [
            snapshot("Bench", weight: 80, reps: 4, trend: .flat),
            snapshot("Squat", weight: 100, reps: 5, trend: .declining),
        ], weeklySets: [.chest: 2], goal: .strength)
        let recs = RecommendationEngine.run(f)
        XCTAssertFalse(recs.isEmpty)
        for rec in recs {
            XCTAssertTrue(known.contains(rec.citation.id), "\(rec.id) cites unknown \(rec.citation.id)")
        }
    }

    func testIdempotentForIdenticalFacts() {
        let f = facts(snapshots: [snapshot("Squat", weight: 100, reps: 4, trend: .flat)],
                      weeklySets: [.chest: 2], goal: .strength)
        XCTAssertEqual(RecommendationEngine.run(f).map(\.id), RecommendationEngine.run(f).map(\.id))
    }

    func testRoundLoadSnapsToIncrement() {
        XCTAssertEqual(PrescriptionMath.roundLoad(101.2), 100)
        XCTAssertEqual(PrescriptionMath.roundLoad(101.3), 102.5)
        XCTAssertEqual(PrescriptionMath.roundLoad(100), 100)
    }

    // MARK: integration through TrainingFacts.make

    func testMakeWiresLiftSnapshotIntoProgression() throws {
        let ctx = try makeContext()
        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 5; comps.hour = 12; comps.minute = 0; comps.second = 0
        let now = cal.date(from: comps) ?? Date()
        let s = try WorkoutRepository.createSession(date: now.addingTimeInterval(-2 * 86_400), in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(
            named: "BackSquat", primaryMuscles: ["quadriceps"], secondaryMuscles: ["glutes"], in: ctx)
        // 5 reps at 60 kg, strength goal (range 3–5) → at the top → add load to 62.5.
        _ = try WorkoutRepository.addSet(to: s, exercise: squat, weightKg: 60, reps: 5, rpe: 8, in: ctx)
        let f = TrainingFacts.make(sessions: [s], now: now, goal: .strength, experience: .intermediate)
        XCTAssertNotNil(f.liftSnapshots["BackSquat"])
        let rec = RecommendationEngine.run(f).first { $0.id == "progression.BackSquat" }
        XCTAssertEqual(rec?.target?.loadKg, 62.5)
    }

    // MARK: P6 — cardio HIIT/SIT recommendations

    private let day: TimeInterval = 86_400

    private func cardioA(_ kind: AssessmentKind, _ value: Double, daysAgo: Double,
                         now: Date) -> Assessment {
        Assessment(date: now.addingTimeInterval(-daysAgo * day),
                   kind: kind, value: value)
    }

    func testVo2maxDeclineTriggersHIITRecommendation() {
        let now = Date()
        let assessments = [
            cardioA(.vo2maxField, 45, daysAgo: 60, now: now),
            cardioA(.vo2maxField, 38, daysAgo: 2, now: now),  // declined past MDC
        ]
        let f = TrainingFacts.make(sessions: [], assessments: assessments, now: now,
                                    goal: .hypertrophy, experience: .intermediate)
        let rec = RecommendationEngine.run(f).first { $0.id == "cardio.hiit.vo2max" }
        XCTAssertEqual(rec?.kind, .cardioHIIT)
        // New citation: crowleyVO2Intensity2022 (was hiitVo2max)
        XCTAssertEqual(rec?.citation.id, CitationRegistry.crowleyVO2Intensity2022.id)
    }

    func testWingateDeclineNoLongerTriggersSIT() {
        let now = Date()
        let assessments = [
            cardioA(.wingate, 600, daysAgo: 60, now: now),
            cardioA(.wingate, 500, daysAgo: 2, now: now),  // declined past MDC
        ]
        let f = TrainingFacts.make(sessions: [], assessments: assessments, now: now,
                                    goal: .hypertrophy, experience: .intermediate)
        // SIT is now opt-in only — the rule always returns empty.
        let rec = RecommendationEngine.run(f).first { $0.id == "cardio.sit.wingate" }
        XCTAssertNil(rec, "SIT should not be auto-prescribed")
    }

    func testCardioRecHasNoSetTarget() {
        let now = Date()
        let assessments = [
            cardioA(.vo2maxField, 45, daysAgo: 60, now: now),
            cardioA(.vo2maxField, 38, daysAgo: 2, now: now),
        ]
        let f = TrainingFacts.make(sessions: [], assessments: assessments, now: now,
                                   goal: .hypertrophy, experience: .intermediate)
        let rec = RecommendationEngine.run(f).first { $0.id == "cardio.hiit.vo2max" }
        XCTAssertNil(rec?.target, "cardioHIIT recs should not have a SetTarget")
        XCTAssertNotNil(rec?.cardioPrescription)
    }

    func testVo2maxImprovementDoesNotTriggerHIIT() {
        let now = Date()
        let assessments = [
            cardioA(.vo2maxField, 38, daysAgo: 60, now: now),
            cardioA(.vo2maxField, 45, daysAgo: 2, now: now),  // improved
        ]
        let f = TrainingFacts.make(sessions: [], assessments: assessments, now: now,
                                   goal: .hypertrophy, experience: .intermediate)
        XCTAssertNil(RecommendationEngine.run(f).first { $0.id == "cardio.hiit.vo2max" })
    }

    func testCardioRecommendationsAreCited() {
        let now = Date()
        let assessments = [
            cardioA(.vo2maxField, 45, daysAgo: 60, now: now),
            cardioA(.vo2maxField, 38, daysAgo: 2, now: now),
            cardioA(.wingate, 600, daysAgo: 60, now: now),
            cardioA(.wingate, 500, daysAgo: 2, now: now),
        ]
        let f = TrainingFacts.make(sessions: [], assessments: assessments, now: now,
                                   goal: .hypertrophy, experience: .intermediate)
        let known = Set(CitationRegistry.all.map(\.id))
        let recs = RecommendationEngine.run(f).filter { $0.kind == .cardioHIIT }
        XCTAssertFalse(recs.isEmpty)
        for rec in recs {
            XCTAssertTrue(known.contains(rec.citation.id), "\(rec.id) cites unknown \(rec.citation.id)")
        }
    }

    func testAddVolumeCappedAtFourSets() {
        let f = facts(weeklySets: [.chest: 3], goal: .strength)
        let recs = RecommendationEngine.run(f)
        let chestRecs = recs.filter { $0.id.hasPrefix("addVolume.") && $0.part == .chest }
        XCTAssertFalse(chestRecs.isEmpty, "Should recommend volume for chest below MEV")
        for rec in chestRecs {
            if let target = rec.target, let sets = target.sets {
                XCTAssertLessThanOrEqual(sets, 4, "addVolume should cap at 4 sets max, got \(sets)")
                XCTAssertGreaterThanOrEqual(sets, 1, "addVolume should recommend at least 1 set")
            }
        }
    }

    // MARK: - Phase 3: multi-system CoachRecommendationEngine rules

    private var coachNow: Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 5; comps.hour = 12; comps.minute = 0; comps.second = 0
        return cal.date(from: comps) ?? Date()
    }

    private func strengthEvent(_ c: ModelContext, name: String, muscles: [String], reps: Int,
                               sets: Int, daysAgo: Double, now: Date, rpe: Double = 8,
                               weight: Double = 100) throws -> TrainingEvent {
        let date = now.addingTimeInterval(-daysAgo * 86_400)
        let s = try WorkoutRepository.createSession(date: date.addingTimeInterval(-600), in: c)
        let ex = try WorkoutRepository.findOrCreateExercise(named: name, primaryMuscles: muscles, in: c)
        for _ in 0..<sets {
            _ = try WorkoutRepository.addSet(to: s, exercise: ex, weightKg: weight, reps: reps, rpe: rpe, in: c)
        }
        s.endedAt = date
        return TrainingEvent.from(session: s)!
    }

    private func cardioEvent(_ c: ModelContext, type: CardioType, daysAgo: Double,
                             now: Date, duration: TimeInterval = 1800, avgHR: Double?) -> TrainingEvent {
        let start = now.addingTimeInterval(-daysAgo * 86_400)
        let cardio = CardioWorkout(type: type, start: start, end: start.addingTimeInterval(duration),
                                   avgHeartRate: avgHR, source: .iphone)
        c.insert(cardio)
        return TrainingEvent.from(cardio: cardio)
    }

    private func vo2Summary(latest: Double, baseline: Double, now: Date) -> AssessmentSummary {
        AssessmentSummary(kind: .vo2maxField, exerciseName: nil, latest: latest,
                          latestDate: now.addingTimeInterval(-5 * 86_400), baseline: baseline,
                          baselineDate: now.addingTimeInterval(-40 * 86_400),
                          best: max(latest, baseline), count: 2)
    }

    func testStrengthBlockUsesGoalSpecificRepTargetsAndCitesPeriodization() throws {
        let c = try makeContext()
        let now = coachNow
        let e1 = try strengthEvent(c, name: "Squat", muscles: ["quadriceps"], reps: 4, sets: 3, daysAgo: 1, now: now)
        let e2 = try strengthEvent(c, name: "Bench", muscles: ["chest"], reps: 4, sets: 3, daysAgo: 8, now: now)
        let facts = CoachFacts.make(from: [e1, e2], goal: .strength, experience: .intermediate, now: now)
        let recs = CoachRecommendationEngine.run(facts)
        let block = recs.first { $0.id == "strengthBlock" }
        XCTAssertNotNil(block)
        XCTAssertEqual(block?.target?.repsLow, TrainingGoal.strength.repRange.lowerBound)
        XCTAssertEqual(block?.target?.repsHigh, TrainingGoal.strength.repRange.upperBound)
        XCTAssertEqual(block?.citation.id, "williamsLinearPeriodization")
        XCTAssertTrue(block?.citationIds.contains("schoenfeld2021") ?? false)
        XCTAssertEqual(block?.evidenceCategory, .periodization)
    }

    func testVolumeIncreaseFiresBelowMEVAndUsesFrequencyCitationForFrequencyClaim() throws {
        let c = try makeContext()
        let now = coachNow
        // 2 chest sets this week → below intermediate MEV (8).
        let e = try strengthEvent(c, name: "Bench", muscles: ["chest"], reps: 8, sets: 2, daysAgo: 1, now: now)
        let facts = CoachFacts.make(from: [e], goal: .hypertrophy, experience: .intermediate, now: now)
        let rec = CoachRecommendationEngine.run(facts).first { $0.id == "volumeAdjust.add.chest" }
        XCTAssertNotNil(rec)
        XCTAssertEqual(rec?.citation.id, "volumeDoseResponse")           // volume claim → volume citation
        XCTAssertTrue(rec?.citationIds.contains("frequencyMeta") ?? false) // frequency sub-claim → frequency citation
        XCTAssertNotEqual(rec?.citation.id, "frequencyMeta")
    }

    func testHighVolumePlusPoorReadinessSuggestsHoldOrReduce() throws {
        let c = try makeContext()
        let now = coachNow
        // 24 chest sets → over intermediate MRV (22).
        let e = try strengthEvent(c, name: "Bench", muscles: ["chest"], reps: 10, sets: 24, daysAgo: 1, now: now)
        let readiness = ReadinessEntry(date: now, muscleSoreness: 2, fatigueEnergy: 2,
                                       sleepQuality: 2, stressMood: 3)
        let facts = CoachFacts.make(from: [e], goal: .hypertrophy, experience: .intermediate,
                                    readinessEntry: readiness, now: now)
        XCTAssertNotNil(CoachRecommendationEngine.run(facts).first { $0.id == "volumeAdjust.reduce.chest" })
    }

    func testAerobicBaseUsesActivityCitationsAndNeverCalls150Optimal() throws {
        let now = coachNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let rec = CoachRecommendationEngine.run(facts).first { $0.id == "aerobicBase" }
        XCTAssertNotNil(rec)
        XCTAssertEqual(rec?.evidenceCategory, .aerobicBase)
        XCTAssertTrue(CitationRegistry.aerobicBasePool.citationIds.contains(rec!.citation.id))
        XCTAssertFalse(rec!.detail.localizedCaseInsensitiveContains("optimal"))
        XCTAssertFalse(rec!.action.localizedCaseInsensitiveContains("optimal"))
    }

    func testBeginnerAerobicBaseSaysDurationBeforeIntensity() throws {
        let now = coachNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .beginner, now: now)
        let rec = CoachRecommendationEngine.run(facts).first { $0.id == "aerobicBase" }
        XCTAssertTrue(rec?.action.localizedCaseInsensitiveContains("duration before intensity") ?? false)
    }

    func testVO2RuleExcludesBeginnersAndCitesVO2Pool() throws {
        let c = try makeContext()
        let now = coachNow
        let base = cardioEvent(c, type: .run, daysAgo: 2, now: now, avgHR: 130)  // moderate base
        let vo2 = vo2Summary(latest: 40, baseline: 45, now: now)                 // declined

        let beginner = CoachFacts.make(from: [base], goal: .strength, experience: .beginner,
                                       assessments: [vo2], now: now)
        XCTAssertNil(CoachRecommendationEngine.run(beginner).first { $0.id == "vo2Intervals" })

        let inter = CoachFacts.make(from: [base], goal: .strength, experience: .intermediate,
                                    assessments: [vo2], now: now)
        let rec = CoachRecommendationEngine.run(inter).first { $0.id == "vo2Intervals" }
        XCTAssertNotNil(rec)
        XCTAssertEqual(rec?.citation.id, "crowleyVO2Intensity2022")
        let vo2Pool = Set(CitationRegistry.vo2TrainingPool.citationIds)
        XCTAssertTrue(([rec!.citation.id] + rec!.citationIds).allSatisfy { vo2Pool.contains($0) })
    }

    func testThresholdRuleLowConfidenceWithEstimatedHRAndNoMortalityCitation() throws {
        let c = try makeContext()
        let now = coachNow
        // Moderate base with HR → aerobic base not stale, zoneSource = ageEstimated.
        let base = cardioEvent(c, type: .cycle, daysAgo: 2, now: now, avgHR: 130)
        let facts = CoachFacts.make(from: [base], goal: .endurance, experience: .intermediate, now: now)
        let rec = CoachRecommendationEngine.run(facts).first { $0.id == "thresholdTempo" }
        XCTAssertNotNil(rec)
        XCTAssertEqual(rec?.citation.id, "kaufmannThreshold2023")
        XCTAssertEqual(rec?.confidence, .low)
        XCTAssertTrue(rec?.citationIds.contains("tanakaMaxHR2001") ?? false)
        let mortality: Set<String> = ["ekelundActivityMortality2016", "mooreLeisureActivity2012",
                                      "aremDoseResponse2015", "saintMauriceSteps2020", "leeAccelerometer2019"]
        XCTAssertTrue(Set([rec!.citation.id] + rec!.citationIds).isDisjoint(with: mortality))
    }

    func testAnaerobicIsDefaultWhenEligibleAndPreferenceRanked() throws {
        let c = try makeContext()
        let now = coachNow
        let base = cardioEvent(c, type: .run, daysAgo: 3, now: now, avgHR: 130)

        let inter = CoachFacts.make(from: [base], goal: .strength, experience: .intermediate, now: now)
        let interRecs = CoachRecommendationEngine.run(inter)
        let rec = interRecs.first { $0.id == "anaerobicOptIn" }
        XCTAssertNotNil(rec)
        XCTAssertFalse(rec!.riskNotes.isEmpty)
        let pool = Set(CitationRegistry.anaerobicTrainingPool.citationIds)
        XCTAssertTrue(Set([rec!.citation.id] + rec!.citationIds).allSatisfy { pool.contains($0) })

        let easyChoice = CoachSession(
            id: "aerobic.easyWalk", kind: .easyAerobic, title: "Easy walk",
            durationMinutes: 30, modality: .walk, intensity: .easy,
            trainingLoadTags: ["aerobic", "easy", "lowImpact"],
            launchPayload: .cardio(type: "walk", durationMinutes: 30)
        )
        let sprintAlternative = CoachSession(
            id: "aerobic.anaerobicIntervals", kind: .vo2Intervals, title: "Sprint intervals",
            durationMinutes: 20, modality: .run, intensity: .vigorous,
            trainingLoadTags: ["aerobic", "hard", "highImpact", "anaerobic"],
            launchPayload: .cardio(type: "hiit", durationMinutes: 20)
        )
        var profile = CoachPreferenceProfile.empty
        profile.recordSelection(easyChoice, from: [sprintAlternative], at: now)
        profile.recordSelection(easyChoice, from: [sprintAlternative], at: now.addingTimeInterval(60))
        let rankedDown = CoachRecommendationEngine.run(inter, profile: profile)
            .first { $0.id == "anaerobicOptIn" }
        XCTAssertNotNil(rankedDown)
        XCTAssertLessThan(rankedDown!.priority, rec!.priority)

        let advanced = CoachFacts.make(from: [base], goal: .strength, experience: .advanced, now: now)
        XCTAssertNotNil(CoachRecommendationEngine.run(advanced).first { $0.id == "anaerobicOptIn" })
    }

    func testFlexibilityRuleUsesROMCitationAndNoInjuryPreventionOverclaim() throws {
        let now = coachNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let rec = CoachRecommendationEngine.run(facts).first { $0.id == "flexibility" }
        XCTAssertNotNil(rec)
        XCTAssertEqual(rec?.citation.id, "konradStretchROM2024")
        XCTAssertEqual(rec?.evidenceCategory, .flexibilityROM)
        XCTAssertFalse(rec!.citationIds.contains("lauersenInjuryPrevention2014"))
        XCTAssertFalse(rec!.detail.localizedCaseInsensitiveContains("prevents all injuries"))
    }

    func testPoorReadinessEmitsRecoveryAndDoesNotDiagnoseOvertraining() throws {
        let now = coachNow
        let readiness = ReadinessEntry(date: now, muscleSoreness: 1, fatigueEnergy: 2,
                                       sleepQuality: 2, stressMood: 2)
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate,
                                    readinessEntry: readiness, now: now)
        let recs = CoachRecommendationEngine.run(facts)
        let rec = recs.first { $0.id == "recoveryReadiness" }
        XCTAssertNotNil(rec)
        XCTAssertEqual(recs.first?.kind, .recoveryReadiness)   // highest priority when readiness poor
        XCTAssertEqual(rec?.citation.id, "sawMonitoring2016")
        let monitoring = Set(CitationRegistry.recoveryMonitoringPool.citationIds)
        XCTAssertTrue(Set([rec!.citation.id] + rec!.citationIds).allSatisfy { monitoring.contains($0) })
        for s in [rec!.title, rec!.action, rec!.detail] {
            XCTAssertFalse(s.localizedCaseInsensitiveContains("overtrain"))
        }
    }

    func testMissingVO2BaselinePromptsCardioAssessmentWithSource() throws {
        let c = try makeContext()
        let now = coachNow
        let base = cardioEvent(c, type: .run, daysAgo: 2, now: now, avgHR: 130)  // base, no vo2 baseline
        let facts = CoachFacts.make(from: [base], goal: .strength, experience: .intermediate, now: now)
        let rec = CoachRecommendationEngine.run(facts).first { $0.id == "assessmentPrompt.vo2max" }
        XCTAssertNotNil(rec)
        XCTAssertEqual(rec?.citation.id, "cooperVo2max")
        XCTAssertEqual(rec?.evidenceCategory, .fieldTestValidity)
        XCTAssertTrue(CitationRegistry.fieldTestValidityPool.citationIds.contains(rec!.citation.id))
    }

    // MARK: - Unused-citation integration (2026-07-07)

    func testHIITVo2maxInVo2Pool() {
        XCTAssertTrue(CitationRegistry.vo2TrainingPool.citationIds.contains("hiitVo2max"),
                      "hiitVo2max should broaden the VO₂-training evidence base")
    }

    func testDrewFinchInRecoveryPool() {
        XCTAssertTrue(CitationRegistry.recoveryMonitoringPool.citationIds.contains("drewFinchInjury2016"),
                      "drewFinchInjury2016 should back recovery/load warnings")
    }

    func testLauersenInInjuryPreventionPoolNotFlexibility() {
        XCTAssertTrue(CitationRegistry.injuryPreventionPool.citationIds.contains("lauersenInjuryPrevention2014"),
                      "lauersenInjuryPrevention2014 belongs in the injury-prevention pool")
        XCTAssertFalse(CitationRegistry.flexibilityROMPool.citationIds.contains("lauersenInjuryPrevention2014"),
                       "lauersenInjuryPrevention2014 must never back a flexibility/ROM claim")
    }
}
