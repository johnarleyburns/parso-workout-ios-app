#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

/// strength-pivot P5.1 — the prescriptive inference engine over `TrainingFacts`.
struct RecommendationEngineTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    /// Build a synthetic facts snapshot directly (bypassing the store) for
    /// table-driven rule tests, mirroring how `TrainingFacts.make` would fill it.
    private func facts(snapshots: [LiftSnapshot] = [],
                       weeklySets: [MuscleGroup: Double] = [:],
                       goal: TrainingGoal = .strength,
                       experience: ExperienceLevel = .intermediate) -> TrainingFacts {
        TrainingFacts(
            weeklySetsByGroup: weeklySets,
            frequencyByGroup: [:],
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
                          trend: TrendDirection?, group: MuscleGroup? = .quadriceps) -> LiftSnapshot {
        LiftSnapshot(exercise: name, group: group, topSetWeightKg: weight,
                     topSetReps: reps, bestE1RM: weight, trend: trend)
    }

    // MARK: cold-start

    @Test func coldStartReturnsStarter() {
        let recs = RecommendationEngine.run(facts())
        #expect(recs.count == 1)
        #expect(recs.first?.kind == .starter)
        #expect(recs.first?.target != nil)
        #expect(RecommendationEngine.top(facts()).kind == .starter)
    }

    @Test func starterUsesGoalRepRangeAndRIR() {
        let starter = KnowledgeBase.starter(goal: .hypertrophy, experience: .intermediate)
        #expect(starter.target?.repsLow == 6)
        #expect(starter.target?.repsHigh == 12)
        #expect(starter.target?.rir == 1)
        #expect(starter.target?.sets == 3)
    }

    // MARK: progression (double progression)

    @Test func addsRepWhenBelowTopOfRange() {
        // strength range 3–5; 4 reps → aim for 5 at the same load.
        let f = facts(snapshots: [snapshot("Squat", weight: 100, reps: 4, trend: .flat)], goal: .strength)
        let rec = RecommendationEngine.run(f).first { $0.id == "progression.Squat" }
        #expect(rec?.target?.repsLow == 5)
        #expect(rec?.target?.repsHigh == 5)
        #expect(rec?.target?.loadKg == 100)        // same load
        #expect(rec?.target?.rir == 2)
        #expect(rec?.confidence == .high)          // flat = clear plateau cue
    }

    @Test func addsLoadAtTopOfRange() {
        // strength range 3–5; already at 5 reps → add 2.5 kg, reset to 3 reps.
        let f = facts(snapshots: [snapshot("Squat", weight: 100, reps: 5, trend: .rising)], goal: .strength)
        let rec = RecommendationEngine.run(f).first { $0.id == "progression.Squat" }
        #expect(rec?.target?.loadKg == 102.5)
        #expect(rec?.target?.repsLow == 3)         // reset to bottom
        #expect(rec?.confidence == .moderate)      // rising = keep going
    }

    // MARK: deload

    @Test func decliningLiftGetsDeloadNotProgression() {
        let f = facts(snapshots: [snapshot("Squat", weight: 100, reps: 5, trend: .declining)], goal: .strength)
        let recs = RecommendationEngine.run(f)
        #expect(recs.first { $0.id == "progression.Squat" } == nil)
        let deload = recs.first { $0.id == "deload.Squat" }
        #expect(deload?.kind == .deload)
        #expect(deload?.target?.loadKg == 90)      // ~10% off, rounded to 2.5
        #expect(deload?.target?.rir == 3)          // more in reserve
        #expect(deload?.citation.id == CitationRegistry.rpeAutoregulation.id)
    }

    @Test func deloadDoesNotOutrankProgression() {
        let f = facts(snapshots: [
            snapshot("Bench", weight: 80, reps: 4, trend: .flat),       // → progression (pri 100)
            snapshot("Squat", weight: 100, reps: 5, trend: .declining), // → deload (pri 95, now below progression)
        ], goal: .strength)
        // Progression now outranks deload — single-week decline is monitored, not blocked.
        #expect(RecommendationEngine.run(f).first?.id == "progression.Bench")
    }

    // MARK: add volume

    @Test func addVolumeBelowMEV() {
        // 2 sets/week is below the minimum effective volume for any part.
        let f = facts(weeklySets: [.chest: 2], goal: .hypertrophy)
        let rec = RecommendationEngine.run(f).first { $0.id == "addVolume.chest" }
        #expect(rec?.kind == .addVolume)
        #expect(rec?.group == .chest)
        #expect(rec?.target?.loadKg == nil)               // volume, not a specific load
        #expect((rec?.target?.sets ?? 0) >= 1)
        #expect(rec?.citation.id == CitationRegistry.volumeDoseResponse.id)
    }

    @Test func productiveVolumeProducesNoAddVolume() {
        // A large weekly volume is well above MEV → no add-volume recommendation.
        let f = facts(weeklySets: [.chest: 40], goal: .hypertrophy)
        #expect(RecommendationEngine.run(f).first { $0.id == "addVolume.chest" } == nil)
    }

    // MARK: invariants

    @Test func everyRecommendationIsCited() {
        let known = Set(CitationRegistry.all.map(\.id))
        let f = facts(snapshots: [
            snapshot("Bench", weight: 80, reps: 4, trend: .flat),
            snapshot("Squat", weight: 100, reps: 5, trend: .declining),
        ], weeklySets: [.chest: 2], goal: .strength)
        let recs = RecommendationEngine.run(f)
        #expect(!recs.isEmpty)
        for rec in recs {
            #expect(known.contains(rec.citation.id), "\(rec.id) cites unknown \(rec.citation.id)")
        }
    }

    @Test func idempotentForIdenticalFacts() {
        let f = facts(snapshots: [snapshot("Squat", weight: 100, reps: 4, trend: .flat)],
                      weeklySets: [.chest: 2], goal: .strength)
        #expect(RecommendationEngine.run(f).map(\.id) == RecommendationEngine.run(f).map(\.id))
    }

    @Test func roundLoadSnapsToIncrement() {
        #expect(PrescriptionMath.roundLoad(101.2) == 100)
        #expect(PrescriptionMath.roundLoad(101.3) == 102.5)
        #expect(PrescriptionMath.roundLoad(100) == 100)
    }

    // MARK: integration through TrainingFacts.make

    @Test func makeWiresLiftSnapshotIntoProgression() throws {
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
        #expect(f.liftSnapshots["BackSquat"] != nil)
        let rec = RecommendationEngine.run(f).first { $0.id == "progression.BackSquat" }
        #expect(rec?.target?.loadKg == 62.5)
    }

    // MARK: P6 — cardio HIIT/SIT recommendations

    private let day: TimeInterval = 86_400

    private func cardioA(_ kind: AssessmentKind, _ value: Double, daysAgo: Double,
                         now: Date) -> Assessment {
        Assessment(date: now.addingTimeInterval(-daysAgo * day),
                   kind: kind, value: value)
    }

    @Test func vo2maxDeclineTriggersHIITRecommendation() {
        let now = Date()
        let assessments = [
            cardioA(.vo2maxField, 45, daysAgo: 60, now: now),
            cardioA(.vo2maxField, 38, daysAgo: 2, now: now),  // declined past MDC
        ]
        let f = TrainingFacts.make(sessions: [], assessments: assessments, now: now,
                                    goal: .hypertrophy, experience: .intermediate)
        let rec = RecommendationEngine.run(f).first { $0.id == "cardio.hiit.vo2max" }
        #expect(rec?.kind == .cardioHIIT)
        // New citation: crowleyVO2Intensity2022 (was hiitVo2max)
        #expect(rec?.citation.id == CitationRegistry.crowleyVO2Intensity2022.id)
    }

    @Test func wingateDeclineNoLongerTriggersSIT() {
        let now = Date()
        let assessments = [
            cardioA(.wingate, 600, daysAgo: 60, now: now),
            cardioA(.wingate, 500, daysAgo: 2, now: now),  // declined past MDC
        ]
        let f = TrainingFacts.make(sessions: [], assessments: assessments, now: now,
                                    goal: .hypertrophy, experience: .intermediate)
        // SIT is now opt-in only — the rule always returns empty.
        let rec = RecommendationEngine.run(f).first { $0.id == "cardio.sit.wingate" }
        #expect(rec == nil, "SIT should not be auto-prescribed")
    }

    @Test func cardioRecHasNoSetTarget() {
        let now = Date()
        let assessments = [
            cardioA(.vo2maxField, 45, daysAgo: 60, now: now),
            cardioA(.vo2maxField, 38, daysAgo: 2, now: now),
        ]
        let f = TrainingFacts.make(sessions: [], assessments: assessments, now: now,
                                   goal: .hypertrophy, experience: .intermediate)
        let rec = RecommendationEngine.run(f).first { $0.id == "cardio.hiit.vo2max" }
        #expect(rec?.target == nil, "cardioHIIT recs should not have a SetTarget")
        #expect(rec?.cardioPrescription != nil)
    }

    @Test func vo2maxImprovementDoesNotTriggerHIIT() {
        let now = Date()
        let assessments = [
            cardioA(.vo2maxField, 38, daysAgo: 60, now: now),
            cardioA(.vo2maxField, 45, daysAgo: 2, now: now),  // improved
        ]
        let f = TrainingFacts.make(sessions: [], assessments: assessments, now: now,
                                   goal: .hypertrophy, experience: .intermediate)
        #expect(RecommendationEngine.run(f).first { $0.id == "cardio.hiit.vo2max" } == nil)
    }

    @Test func cardioRecommendationsAreCited() {
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
        #expect(!recs.isEmpty)
        for rec in recs {
            #expect(known.contains(rec.citation.id), "\(rec.id) cites unknown \(rec.citation.id)")
        }
    }

    @Test func addVolumeCappedAtFourSets() {
        let f = facts(weeklySets: [.chest: 3], goal: .strength)
        let recs = RecommendationEngine.run(f)
        let chestRecs = recs.filter { $0.id.hasPrefix("addVolume.") && $0.group == .chest }
        #expect(!chestRecs.isEmpty, "Should recommend volume for chest below MEV")
        for rec in chestRecs {
            if let target = rec.target, let sets = target.sets {
                #expect(sets <= 4, "addVolume should cap at 4 sets max, got \(sets)")
                #expect(sets >= 1, "addVolume should recommend at least 1 set")
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

    @Test func strengthBlockUsesGoalSpecificRepTargetsAndCitesPeriodization() throws {
        let c = try makeContext()
        let now = coachNow
        let e1 = try strengthEvent(c, name: "Squat", muscles: ["quadriceps"], reps: 4, sets: 3, daysAgo: 1, now: now)
        let e2 = try strengthEvent(c, name: "Bench", muscles: ["chest"], reps: 4, sets: 3, daysAgo: 8, now: now)
        let facts = CoachFacts.make(from: [e1, e2], goal: .strength, experience: .intermediate, now: now)
        let recs = CoachRecommendationEngine.run(facts)
        let block = recs.first { $0.id == "strengthBlock" }
        #expect(block != nil)
        #expect(block?.target?.repsLow == TrainingGoal.strength.repRange.lowerBound)
        #expect(block?.target?.repsHigh == TrainingGoal.strength.repRange.upperBound)
        #expect(block?.citation.id == "williamsLinearPeriodization")
        #expect(block?.citationIds.contains("schoenfeld2021") ?? false)
        #expect(block?.evidenceCategory == .periodization)
    }

    @Test func volumeIncreaseFiresBelowMEVAndUsesFrequencyCitationForFrequencyClaim() throws {
        let c = try makeContext()
        let now = coachNow
        // 2 chest sets this week → below intermediate MEV (8).
        let e = try strengthEvent(c, name: "Bench", muscles: ["chest"], reps: 8, sets: 2, daysAgo: 1, now: now)
        let facts = CoachFacts.make(from: [e], goal: .hypertrophy, experience: .intermediate, now: now)
        let rec = CoachRecommendationEngine.run(facts).first { $0.id == "volumeAdjust.add.chest" }
        #expect(rec != nil)
        #expect(rec?.citation.id == "volumeDoseResponse")           // volume claim → volume citation
        #expect(rec?.citationIds.contains("frequencyMeta") ?? false) // frequency sub-claim → frequency citation
        #expect(rec?.citation.id != "frequencyMeta")
    }

    @Test func highVolumePlusPoorReadinessSuggestsHoldOrReduce() throws {
        let c = try makeContext()
        let now = coachNow
        // 24 chest sets → over intermediate MRV (22).
        let e = try strengthEvent(c, name: "Bench", muscles: ["chest"], reps: 10, sets: 24, daysAgo: 1, now: now)
        let readiness = ReadinessEntry(date: now, muscleSoreness: 2, fatigueEnergy: 2,
                                       sleepQuality: 2, stressMood: 3)
        let facts = CoachFacts.make(from: [e], goal: .hypertrophy, experience: .intermediate,
                                    readinessEntry: readiness, now: now)
        #expect(CoachRecommendationEngine.run(facts).first { $0.id == "volumeAdjust.reduce.chest" } != nil)
    }

    @Test func aerobicBaseUsesActivityCitationsAndNeverCalls150Optimal() throws {
        let now = coachNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let rec = CoachRecommendationEngine.run(facts).first { $0.id == "aerobicBase" }
        #expect(rec != nil)
        #expect(rec?.evidenceCategory == .aerobicBase)
        #expect(CitationRegistry.aerobicBasePool.citationIds.contains(rec!.citation.id))
        #expect(!rec!.detail.localizedCaseInsensitiveContains("optimal"))
        #expect(!rec!.action.localizedCaseInsensitiveContains("optimal"))
    }

    @Test func beginnerAerobicBaseSaysDurationBeforeIntensity() throws {
        let now = coachNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .beginner, now: now)
        let rec = CoachRecommendationEngine.run(facts).first { $0.id == "aerobicBase" }
        #expect(rec?.action.localizedCaseInsensitiveContains("duration before intensity") ?? false)
    }

    @Test func vO2RuleExcludesBeginnersAndCitesVO2Pool() throws {
        let c = try makeContext()
        let now = coachNow
        let base = cardioEvent(c, type: .run, daysAgo: 2, now: now, avgHR: 130)  // moderate base
        let vo2 = vo2Summary(latest: 40, baseline: 45, now: now)                 // declined

        let beginner = CoachFacts.make(from: [base], goal: .strength, experience: .beginner,
                                       assessments: [vo2], now: now)
        #expect(CoachRecommendationEngine.run(beginner).first { $0.id == "vo2Intervals" } == nil)

        let inter = CoachFacts.make(from: [base], goal: .strength, experience: .intermediate,
                                    assessments: [vo2], now: now)
        let rec = CoachRecommendationEngine.run(inter).first { $0.id == "vo2Intervals" }
        #expect(rec != nil)
        #expect(rec?.citation.id == "crowleyVO2Intensity2022")
        let vo2Pool = Set(CitationRegistry.vo2TrainingPool.citationIds)
        #expect(([rec!.citation.id] + rec!.citationIds).allSatisfy { vo2Pool.contains($0) })
    }

    @Test func thresholdRuleLowConfidenceWithEstimatedHRAndNoMortalityCitation() throws {
        let c = try makeContext()
        let now = coachNow
        // Moderate base with HR → aerobic base not stale, zoneSource = ageEstimated.
        let base = cardioEvent(c, type: .cycle, daysAgo: 2, now: now, avgHR: 130)
        let facts = CoachFacts.make(from: [base], goal: .endurance, experience: .intermediate, now: now)
        let rec = CoachRecommendationEngine.run(facts).first { $0.id == "thresholdTempo" }
        #expect(rec != nil)
        #expect(rec?.citation.id == "kaufmannThreshold2023")
        #expect(rec?.confidence == .low)
        #expect(rec?.citationIds.contains("tanakaMaxHR2001") ?? false)
        let mortality: Set<String> = ["ekelundActivityMortality2016", "mooreLeisureActivity2012",
                                      "aremDoseResponse2015", "saintMauriceSteps2020", "leeAccelerometer2019"]
        #expect(Set([rec!.citation.id] + rec!.citationIds).isDisjoint(with: mortality))
    }

    @Test func anaerobicIsDefaultWhenEligibleAndPreferenceRanked() throws {
        let c = try makeContext()
        let now = coachNow
        let base = cardioEvent(c, type: .run, daysAgo: 3, now: now, avgHR: 130)

        let inter = CoachFacts.make(from: [base], goal: .strength, experience: .intermediate, now: now)
        let interRecs = CoachRecommendationEngine.run(inter)
        let rec = interRecs.first { $0.id == "anaerobicOptIn" }
        #expect(rec != nil)
        #expect(!rec!.riskNotes.isEmpty)
        let pool = Set(CitationRegistry.anaerobicTrainingPool.citationIds)
        #expect(Set([rec!.citation.id] + rec!.citationIds).allSatisfy { pool.contains($0) })

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
        #expect(rankedDown != nil)
        #expect(rankedDown!.priority < rec!.priority)

        let advanced = CoachFacts.make(from: [base], goal: .strength, experience: .advanced, now: now)
        #expect(CoachRecommendationEngine.run(advanced).first { $0.id == "anaerobicOptIn" } != nil)
    }

    @Test func flexibilityRuleUsesROMCitationAndNoInjuryPreventionOverclaim() throws {
        let now = coachNow
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: now)
        let rec = CoachRecommendationEngine.run(facts).first { $0.id == "flexibility" }
        #expect(rec != nil)
        #expect(rec?.citation.id == "konradStretchROM2024")
        #expect(rec?.evidenceCategory == .flexibilityROM)
        #expect(!rec!.citationIds.contains("lauersenInjuryPrevention2014"))
        #expect(!rec!.detail.localizedCaseInsensitiveContains("prevents all injuries"))
    }

    @Test func poorReadinessEmitsRecoveryAndDoesNotDiagnoseOvertraining() throws {
        let now = coachNow
        let readiness = ReadinessEntry(date: now, muscleSoreness: 1, fatigueEnergy: 2,
                                       sleepQuality: 2, stressMood: 2)
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate,
                                    readinessEntry: readiness, now: now)
        let recs = CoachRecommendationEngine.run(facts)
        let rec = recs.first { $0.id == "recoveryReadiness" }
        #expect(rec != nil)
        #expect(recs.first?.kind == .recoveryReadiness)   // highest priority when readiness poor
        #expect(rec?.citation.id == "sawMonitoring2016")
        let monitoring = Set(CitationRegistry.recoveryMonitoringPool.citationIds)
        #expect(Set([rec!.citation.id] + rec!.citationIds).allSatisfy { monitoring.contains($0) })
        for s in [rec!.title, rec!.action, rec!.detail] {
            #expect(!s.localizedCaseInsensitiveContains("overtrain"))
        }
    }

    @Test func missingVO2BaselinePromptsCardioAssessmentWithSource() throws {
        let c = try makeContext()
        let now = coachNow
        let base = cardioEvent(c, type: .run, daysAgo: 2, now: now, avgHR: 130)  // base, no vo2 baseline
        let facts = CoachFacts.make(from: [base], goal: .strength, experience: .intermediate, now: now)
        let rec = CoachRecommendationEngine.run(facts).first { $0.id == "assessmentPrompt.vo2max" }
        #expect(rec != nil)
        #expect(rec?.citation.id == "cooperVo2max")
        #expect(rec?.evidenceCategory == .fieldTestValidity)
        #expect(CitationRegistry.fieldTestValidityPool.citationIds.contains(rec!.citation.id))
    }

    // MARK: - Unused-citation integration (2026-07-07)

    @Test func hIITVo2maxInVo2Pool() {
        #expect(CitationRegistry.vo2TrainingPool.citationIds.contains("hiitVo2max"),
                      "hiitVo2max should broaden the VO₂-training evidence base")
    }

    @Test func drewFinchInRecoveryPool() {
        #expect(CitationRegistry.recoveryMonitoringPool.citationIds.contains("drewFinchInjury2016"),
                      "drewFinchInjury2016 should back recovery/load warnings")
    }

    @Test func lauersenInInjuryPreventionPoolNotFlexibility() {
        #expect(CitationRegistry.injuryPreventionPool.citationIds.contains("lauersenInjuryPrevention2014"),
                      "lauersenInjuryPrevention2014 belongs in the injury-prevention pool")
        #expect(!CitationRegistry.flexibilityROMPool.citationIds.contains("lauersenInjuryPrevention2014"),
                       "lauersenInjuryPrevention2014 must never back a flexibility/ROM claim")
    }
}
#endif
