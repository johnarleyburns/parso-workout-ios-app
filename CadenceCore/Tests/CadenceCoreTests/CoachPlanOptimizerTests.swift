import XCTest
@testable import CadenceCore

final class CoachPlanOptimizerTests: XCTestCase {
    func testWednesdayRemainingStrengthPlanClearsPushDeficitsWhenFeasible() {
        let now = fixedWednesday()
        let facts = trainingFacts([
            .chest: 4,
            .shoulders: 2,
            .triceps: 2,
        ])
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByPart, strengthDays: 1, cardioDays: 2)
        let plan = weeklyPlan(now: now, days: [
            (1, [.strength]),
            (2, [.rest]),
        ])
        let prefs = preferences(twoADays: true)

        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: plan,
            schedulePreferences: prefs,
            candidates: [genericStrengthSession()])

        // With whole-body coverage and only 1 slot, not all 8 body parts can
        // reach MEV. But the coach plans a valid session covering the core
        // deficits.
        XCTAssertEqual(optimized.plannedStrengthSessions.count, 1)
        let names = optimized.plannedStrengthSessions.flatMap { $0.exercises ?? [] }.map(\.name)
        XCTAssertTrue(names.contains("Bench Press"),
                      "Chest deficit (4→8 MEV) should be addressed")

        // Chest had the most completed volume, so it should be resolved.
        let chestDeficit = optimized.unresolvedDeficits[.chest]
        XCTAssertTrue(chestDeficit == nil || (chestDeficit ?? 0) <= 0,
                      "Chest should be at or above MEV")

        let insights = PlanAwareInsightEngine.run(
            completed: facts,
            plan: plan,
            plannedStrengthSessions: optimized.plannedStrengthSessions,
            unresolvedDeficits: optimized.unresolvedDeficits,
            diagnostics: optimized.diagnostics,
            now: now)

        // Trained parts must never show "low volume" nags.
        XCTAssertNil(lowVolumeInsight(.chest, in: insights))
        XCTAssertNil(lowVolumeInsight(.shoulders, in: insights))
        XCTAssertNil(lowVolumeInsight(.triceps, in: insights))

        // Genuinely unresolved deficits surface via the aggregate only.
        if !optimized.unresolvedDeficits.isEmpty {
            XCTAssertNotNil(insights.first { $0.id == "planning.unresolvedVolume" })
        }
    }

    func testOptimizerDoesNotBlindlyRepeatGenericFallbackForFutureStrengthSlots() {
        let now = fixedWednesday()
        let facts = trainingFacts([
            .chest: 4,
            .shoulders: 2,
            .triceps: 2,
        ])
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByPart, strengthDays: 0)
        let plan = weeklyPlan(now: now, days: [
            (1, [.strength]),
            (3, [.strength]),
        ])
        let generic = genericStrengthSession()

        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: plan,
            schedulePreferences: preferences(twoADays: false),
            candidates: [generic])

        // Two planned sessions should cover different body-part gaps (the
        // optimizer reshapes each session against remaining deficits, and the
        // even split spreads isolation evenly), never returning identical copies.
        XCTAssertEqual(optimized.plannedStrengthSessions.count, 2)
        let sessions = optimized.plannedStrengthSessions
        let firstNames = Set((sessions.first?.exercises ?? []).map(\.name))
        let secondNames = Set((sessions.last?.exercises ?? []).map(\.name))
        let allNames = firstNames.union(secondNames)
        XCTAssertGreaterThan(allNames.count, firstNames.count,
                             "Two planned sessions should not have identical exercise lists")
    }

    func testImpossibleCaseEmitsOneUnresolvedPlanningInsight() {
        let now = fixedWednesday()
        let facts = trainingFacts([
            .legs: 1,
            .back: 1,
            .chest: 1,
            .shoulders: 1,
            .biceps: 1,
            .triceps: 1,
            .calves: 1,
            .abs: 1,
        ])
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByPart, strengthDays: 1)
        let plan = weeklyPlan(now: now, days: [
            (1, [.strength]),
        ])

        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: plan,
            schedulePreferences: preferences(twoADays: false),
            candidates: [genericStrengthSession()])

        XCTAssertFalse(optimized.unresolvedDeficits.isEmpty)

        let insights = PlanAwareInsightEngine.run(
            completed: facts,
            plan: plan,
            plannedStrengthSessions: optimized.plannedStrengthSessions,
            unresolvedDeficits: optimized.unresolvedDeficits,
            diagnostics: optimized.diagnostics,
            now: now)

        XCTAssertEqual(insights.filter { $0.id == "planning.unresolvedVolume" }.count, 1)
        let individualLowVolume = insights.filter {
            $0.kind == .volume
                && $0.severity == .attention
                && $0.title.localizedCaseInsensitiveContains("low")
                && $0.part != nil
        }
        XCTAssertTrue(individualLowVolume.isEmpty)
    }

    /// Reproduces the "coach paints itself into a corner" bug (Phase 3) — then
    /// verifies the fix: with whole-body weekly coverage, the optimizer plans for
    /// every body part below MEV (including abs/calves with 0 sets) and the
    /// plan-aware layer never nags about parts the coach chose to cover.
    func testMondayPostWorkoutSuppressesUntrainedPartAlertsWhenWeekIsTight() {
        let cal = Calendar(identifier: .gregorian)
        var mondayComps = DateComponents()
        mondayComps.calendar = cal
        mondayComps.year = 2026; mondayComps.month = 6; mondayComps.day = 22  // Monday
        mondayComps.hour = 18   // evening, post-workout
        let now = mondayComps.date ?? Date(timeIntervalSince1970: 1_782_300_000)

        // Monday workout: 2 sets each of chest/back/legs/shoulders, 1 set biceps/triceps.
        let completedSets: [BodyPart: Double] = [
            .chest: 2, .back: 2, .legs: 2, .shoulders: 2,
            .biceps: 1, .triceps: 1,
            .abs: 0, .calves: 0,
        ]
        let facts = TrainingFacts(
            weeklySetsByPart: completedSets,
            frequencyByPart: completedSets.compactMapValues { $0 > 0 ? 1 : nil },
            e1RMTrendByExercise: [:],
            intensity: .empty,
            avgRPE: nil,
            daysSinceLastSession: 1,
            totalWorkingSets: max(1, Int(completedSets.values.reduce(0, +).rounded(.up))),
            allTimeWorkingSets: max(1, Int(completedSets.values.reduce(0, +).rounded(.up))),
            goal: .strength,
            experience: .intermediate)

        let balance = WeeklyBalance(
            strengthDays: 1,
            cardioDays: 0,
            patternsTrained: [],
            bodyPartsTrained: Set(completedSets.keys).filter { completedSets[$0] ?? 0 > 0 },
            fractionalSets: completedSets,
            moderateMinutes: 0,
            vigorousMinutes: 0,
            moderateEquivalentMinutes: 0,
            hardDays: 1,
            consecutiveHardDays: 1,
            vo2maxLatest: nil, vo2maxProtocol: nil, vo2maxTrend: nil,
            readinessAvailable: false,
            dataCompleteness: .moderate)
        let coach = CoachFacts(
            events: [],
            recovery: .empty,
            weeklyBalance: balance,
            goal: .strength,
            experience: .intermediate,
            referenceDate: now,
            rolling72hCompletedEvents: [],
            rolling7dCompletedEvents: [],
            rolling28dCompletedEvents: [])

        // Remaining week has one more strength slot (Wednesday).
        let plan = WeeklyPlan(days: [
            makeDayOutline(date: now, kinds: [.strength], cal: cal),
            makeDayOutline(date: cal.date(byAdding: .day, value: 2, to: now)!, kinds: [.strength], cal: cal),
        ], generatedAt: now)

        let prefs = CoachSchedulePreferences(
            strengthDaysPerWeek: 2,
            cardioDaysPerWeek: 3,
            restPreference: .fixed(days: []),
            allowsTwoADays: false)

        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: plan,
            schedulePreferences: prefs,
            candidates: [genericStrengthSession()])

        let insights = PlanAwareInsightEngine.run(
            completed: facts,
            plan: plan,
            plannedStrengthSessions: optimized.plannedStrengthSessions,
            unresolvedDeficits: optimized.unresolvedDeficits,
            diagnostics: optimized.diagnostics,
            now: now)

        // With whole-body coverage, the optimizer plans for all parts below MEV,
        // including abs/calves. No individual "low volume" attention insight
        // should ever appear for a part the coach chose to cover (even if the
        // plan genuinely cannot close the gap — that's reported via the aggregate).
        let individualLowVolume = insights.filter {
            $0.kind == .volume
                && $0.severity == .attention
                && $0.title.localizedCaseInsensitiveContains("low")
                && $0.part != nil
        }

        let untrainedPartsWithAlerts = individualLowVolume.filter { ins in
            guard let part = ins.part else { return false }
            return (completedSets[part] ?? 0) == 0
        }
        XCTAssertTrue(untrainedPartsWithAlerts.isEmpty,
                      "Should not show individual low-volume alerts for untrained parts (0 completed sets), but got: \(untrainedPartsWithAlerts.map { $0.part?.rawValue ?? "nil" })")

        // For any genuine unresolved deficits, the aggregate insight exists.
        if !optimized.unresolvedDeficits.isEmpty {
            let unresolvedInsight = insights.first { $0.id == "planning.unresolvedVolume" }
            XCTAssertNotNil(unresolvedInsight, "Expected an unresolved planning insight when deficits exist")
        }
    }

    func testOptimizerOutputIsDeterministic() {
        let now = fixedWednesday()
        let facts = trainingFacts([
            .chest: 4,
            .shoulders: 2,
            .triceps: 2,
        ])
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByPart, strengthDays: 1)
        let plan = weeklyPlan(now: now, days: [
            (1, [.strength]),
            (3, [.strength]),
        ])

        let a = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: plan,
            schedulePreferences: preferences(twoADays: true),
            candidates: [genericStrengthSession()])
        let b = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: plan,
            schedulePreferences: preferences(twoADays: true),
            candidates: [genericStrengthSession()])

        XCTAssertEqual(a, b)
    }

    func testOptimizerRespectsScheduleAndRecoveryConstraints() {
        let now = fixedWednesday()
        let facts = trainingFacts([.chest: 2, .shoulders: 2, .triceps: 1])
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByPart, strengthDays: 1)
        let cardioOnlyPlan = weeklyPlan(now: now, days: [
            (1, [.moderateAerobic]),
        ])

        let noTwoADays = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: cardioOnlyPlan,
            schedulePreferences: preferences(twoADays: false),
            candidates: [genericStrengthSession()])
        XCTAssertTrue(noTwoADays.plannedStrengthSessions.isEmpty)

        let fixedRestPlan = weeklyPlan(now: now, days: [
            (1, [.strength]),
        ])
        let fixedRest = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: fixedRestPlan,
            schedulePreferences: CoachSchedulePreferences(
                restPreference: .fixed(days: [.thursday]),
                allowsTwoADays: true),
            candidates: [genericStrengthSession()])
        XCTAssertTrue(fixedRest.plannedStrengthSessions.isEmpty)

        let recoveryEnd = Calendar.current.date(byAdding: .day, value: 2, to: now) ?? now
        let recovery = RecoveryState(
            byExercise: [:],
            byPattern: [:],
            byBodyPart: [:],
            wholeBody: RecoveryWindow(
                lastExposedAt: now,
                hardEligibleAt: recoveryEnd,
                reason: .fatigue,
                confidence: .moderate))
        let recoveryBlocked = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coachFacts(now: now, completedSets: facts.weeklySetsByPart,
                                   strengthDays: 1, recovery: recovery),
            weeklyPlan: fixedRestPlan,
            schedulePreferences: preferences(twoADays: true),
            candidates: [genericStrengthSession()])
        XCTAssertTrue(recoveryBlocked.plannedStrengthSessions.isEmpty)
        XCTAssertTrue(recoveryBlocked.diagnostics.contains { $0.kind == .recoveryBlocked })
    }

    func testTuesdayNoNagForAbsCalvesWhenPlanCoversWholeBody() {
        let cal = Calendar(identifier: .gregorian)
        var tuesdayComps = DateComponents()
        tuesdayComps.calendar = cal
        tuesdayComps.year = 2026; tuesdayComps.month = 6; tuesdayComps.day = 23 // Tuesday
        tuesdayComps.hour = 8  // morning, before any workout
        let now = tuesdayComps.date ?? Date(timeIntervalSince1970: 1_782_300_000)

        // Monday was logged: 4 compounds, 2 sets each — the coach's own workout.
        // Abs and calves = 0 sets because the coach never planned them.
        let completedSets: [BodyPart: Double] = [
            .legs: 2, .chest: 2, .back: 2, .shoulders: 2,
        ]
        let facts = trainingFacts(completedSets)
        let coach = coachFacts(now: now, completedSets: completedSets, strengthDays: 1, cardioDays: 0)

        // 3 strength days configured, 2 remaining slots (Wed + Fri).
        let prefs = CoachSchedulePreferences(
            strengthDaysPerWeek: 3,
            cardioDaysPerWeek: 6,
            restPreference: .fixed(days: []),
            allowsTwoADays: false)

        let plan = weeklyPlan(now: now, days: [
            (1, [.strength]),   // Wednesday
            (3, [.strength]),   // Friday
        ])

        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: plan,
            schedulePreferences: prefs,
            candidates: [genericStrengthSession()])

        let insights = PlanAwareInsightEngine.run(
            completed: facts,
            plan: plan,
            plannedStrengthSessions: optimized.plannedStrengthSessions,
            unresolvedDeficits: optimized.unresolvedDeficits,
            diagnostics: optimized.diagnostics,
            now: now)

        // RED: The coach must never surface a "you're low" alert for a part it
        // chose not to program. Abs and calves had 0 sets because the optimizer
        // excluded them.
        XCTAssertNil(lowVolumeInsight(.abs, in: insights),
                     "Abs should not read 'low' when coach never planned them")
        XCTAssertNil(lowVolumeInsight(.calves, in: insights),
                     "Calves should not read 'low' when coach never planned them")

        // RED: The planned sessions' exercises should include abs and calves work
        // so the user following the coach actually hits every weekly target.
        let allExercises = optimized.plannedStrengthSessions.flatMap { $0.exercises ?? [] }.map(\.name)
        let hasAbWork = allExercises.contains { name in
            ["Plank", "Cable Crunch", "Hanging Leg Raise", "Ab Wheel Rollout"].contains(name)
        }
        let hasCalfWork = allExercises.contains { name in
            ["Standing Calf Raise", "Seated Calf Raise", "Calf Press on Leg Press"].contains(name)
        }
        XCTAssertTrue(hasAbWork,
                      "Planned sessions should include an ab movement so coach covers whole body")
        XCTAssertTrue(hasCalfWork,
                      "Planned sessions should include a calf movement so coach covers whole body")

        // If capacity truly can't reach MEV, we should see an aggregate
        // planning.unresolvedVolume, never per-part "low" nags.
        if !optimized.unresolvedDeficits.isEmpty {
            let unresolvedInsight = insights.first { $0.id == "planning.unresolvedVolume" }
            XCTAssertNotNil(unresolvedInsight,
                            "Expected aggregate planning.unresolvedVolume when deficits remain")
            let untrainedPartsWithAlerts = insights.filter {
                $0.kind == .volume && $0.severity == .attention
                    && $0.title.localizedCaseInsensitiveContains("low")
                    && (completedSets[$0.part ?? .abs] ?? 0) == 0
            }
            XCTAssertTrue(untrainedPartsWithAlerts.isEmpty,
                          "No per-part 'low' nags for parts coach never programmed")
        }
    }

    // MARK: - P2 (issue 1): productive-midpoint volume targeting

    /// The optimizer must prescribe abs toward the *productive* dose (midpoint of
    /// MEV→MAV), not stop at the MEV floor. For an intermediate, abs MEV=6, MAV=12,
    /// so the productive target is 9 sets/week. Given ample slots + capacity, planned
    /// abs sets should reach ~9, not 6.
    func testAbsPlannedTowardProductiveTargetNotMEVFloor() {
        let now = fixedWednesday()
        // Every large part is already at/above MEV so abs is the ONLY deficit —
        // isolates the productive-target behaviour from whole-body coverage noise.
        // Abs at 3 completed sets (below MEV 6); productive target is 9.
        let facts = trainingFacts([
            .legs: 16, .back: 16, .chest: 16, .shoulders: 16,
            .biceps: 14, .triceps: 14, .calves: 12,
            .abs: 3,
        ])
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByPart, strengthDays: 1)
        // Two strength slots so the optimizer has room to prescribe a productive dose.
        let plan = weeklyPlan(now: now, days: [
            (1, [.strength]),
            (3, [.strength]),
        ])
        let absCandidate = CoachSession(
            id: "strength.abs",
            kind: .strength,
            title: "Core",
            durationMinutes: 30,
            exercises: [.init(name: "Cable Crunch", primaryMuscles: ["abdominals"], sets: 3)],
            trainingLoadTags: ["strength"],
            citationIds: ["schoenfeld2021"],
            launchPayload: .strengthPlan("abs"),
            systemsTrained: [.hypertrophy],
            evidenceCategory: .strengthIntensity)

        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: plan,
            schedulePreferences: preferences(twoADays: true),
            candidates: [absCandidate])

        let plannedAbsSets = PlanAwareWeeklyAccounting
            .plannedSetsByPart(from: optimized.plannedStrengthSessions)[.abs] ?? 0
        let projectedAbs = 3 + plannedAbsSets
        let productive = VolumeLandmarks.productiveTarget(for: .abs, experience: .intermediate)
        XCTAssertEqual(productive, 9, "intermediate abs productive target is the MEV/MAV midpoint (6+12)/2 = 9")
        XCTAssertGreaterThanOrEqual(projectedAbs, productive,
            "Abs should be planned toward the productive dose (\(productive)), not the MEV floor — got projected \(projectedAbs)")
        // And there should be no residual below-MEV deficit for abs.
        XCTAssertNil(optimized.unresolvedDeficits[.abs],
                     "Abs trained to a productive dose leaves no below-MEV residual")
    }

    /// Guard: the productive target must never push a part above MRV.
    func testProductiveTargetNeverExceedsMRV() {        let now = fixedWednesday()
        let facts = trainingFacts([.abs: 3, .calves: 3])
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByPart, strengthDays: 0)
        let plan = weeklyPlan(now: now, days: [
            (1, [.strength]), (2, [.strength]), (3, [.strength]), (4, [.strength]),
        ])
        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: plan,
            schedulePreferences: preferences(twoADays: true),
            candidates: [genericStrengthSession()])

        let projected = PlanAwareWeeklyAccounting
            .plannedSetsByPart(from: optimized.plannedStrengthSessions)
        for part in BodyPart.allCases {
            let total = (facts.weeklySetsByPart[part] ?? 0) + (projected[part] ?? 0)
            let mrv = VolumeLandmarks.bands(for: part, experience: .intermediate).mrv
            XCTAssertLessThanOrEqual(total, mrv,
                "\(part) projected \(total) must not exceed MRV \(mrv)")
        }
    }

    // MARK: - P2 (issue 1): reconcile the under-dose + nag contradiction

    /// Reproduces the reporter's contradiction: abs prescribed at a low dose AND a
    /// "still needs attention" nag fires. With productive-midpoint planning +
    /// MEV-based reporting, when abs is planned to a productive dose there is no
    /// residual below-MEV deficit, so the per-part nag and the aggregate both stay
    /// silent for abs.
    func testProductivelyPlannedAbsProducesNoNag() {
        let now = fixedWednesday()
        // Abs is the only deficit; everything else is already covered.
        let facts = trainingFacts([
            .legs: 16, .back: 16, .chest: 16, .shoulders: 16,
            .biceps: 14, .triceps: 14, .calves: 12,
            .abs: 2,
        ])
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByPart, strengthDays: 1)
        let plan = weeklyPlan(now: now, days: [(1, [.strength]), (3, [.strength])])
        let absCandidate = CoachSession(
            id: "strength.abs", kind: .strength, title: "Core", durationMinutes: 30,
            exercises: [.init(name: "Cable Crunch", primaryMuscles: ["abdominals"], sets: 3)],
            trainingLoadTags: ["strength"], citationIds: ["schoenfeld2021"],
            launchPayload: .strengthPlan("abs"),
            systemsTrained: [.hypertrophy], evidenceCategory: .strengthIntensity)

        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: facts, coachFacts: coach, weeklyPlan: plan,
            schedulePreferences: preferences(twoADays: true),
            candidates: [absCandidate])

        let insights = PlanAwareInsightEngine.run(
            completed: facts, plan: plan,
            plannedStrengthSessions: optimized.plannedStrengthSessions,
            unresolvedDeficits: optimized.unresolvedDeficits,
            diagnostics: optimized.diagnostics, now: now)

        XCTAssertNil(optimized.unresolvedDeficits[.abs],
                     "Abs planned to a productive dose leaves no below-MEV residual")
        XCTAssertNil(lowVolumeInsight(.abs, in: insights),
                     "No per-part abs nag when abs is productively covered")
        XCTAssertNil(insights.first { $0.id == "planning.unresolvedVolume" },
                     "No aggregate 'needs attention' nag when the only deficit is productively covered")
    }

    // MARK: - Session-structure classification (evidence: ramosCampoSplit2024)

    func testSessionStructureFactSurfaced() {
        let now = fixedWednesday()

        // A whole-body session (squat, bench, row, RDL) covers ≥5 body parts.
        let fullBody = genericStrengthSession()
        XCTAssertEqual(CoachPlanOptimizer.classifyStructure(of: fullBody), .fullBody)

        let fact = CoachPlanOptimizer.sessionStructureFact(for: fullBody, now: now)
        XCTAssertNotNil(fact)
        XCTAssertEqual(fact?.kind, .sessionStructure)
        XCTAssertEqual(fact?.value, "Full-body")
        XCTAssertFalse((fact?.detail ?? "").isEmpty, "Structure fact must explain the choice")
        XCTAssertEqual(fact?.citationIds, ["ramosCampoSplit2024"],
                       "Session-structure fact must cite the full-body-vs-split study")

        // An upper-only session (bench press) is classified as an upper-body focus.
        let upper = CoachSession(
            id: "strength.upper", kind: .strength, title: "Upper",
            durationMinutes: 30,
            exercises: [.init(name: "Bench Press", sets: 3)],
            launchPayload: .strengthPlan("upper"))
        XCTAssertEqual(CoachPlanOptimizer.classifyStructure(of: upper), .upperFocus)
        XCTAssertEqual(CoachPlanOptimizer.sessionStructureFact(for: upper, now: now)?.value, "Upper body")

        // Non-strength sessions have no structure to explain.
        let rest = CoachSession(id: "rest.full", kind: .rest, title: "Rest", launchPayload: .rest)
        XCTAssertNil(CoachPlanOptimizer.classifyStructure(of: rest))
        XCTAssertNil(CoachPlanOptimizer.sessionStructureFact(for: rest, now: now))
    }

    private func lowVolumeInsight(_ part: BodyPart, in insights: [Insight]) -> Insight? {
        insights.first {
            $0.kind == .volume
                && $0.part == part
                && $0.severity == .attention
                && $0.title.localizedCaseInsensitiveContains("low")
        }
    }

    private func fixedWednesday() -> Date {
        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.year = 2026
        comps.month = 6
        comps.day = 24
        comps.hour = 12
        return comps.date ?? Date(timeIntervalSince1970: 1_782_300_000)
    }

    private func preferences(twoADays: Bool) -> CoachSchedulePreferences {
        CoachSchedulePreferences(
            strengthDaysPerWeek: 2,
            cardioDaysPerWeek: 3,
            restPreference: .fixed(days: []),
            allowsTwoADays: twoADays)
    }

    private func trainingFacts(_ sets: [BodyPart: Double],
                               allTimeSets: Int? = nil) -> TrainingFacts {
        TrainingFacts(
            weeklySetsByPart: sets,
            frequencyByPart: sets.mapValues { _ in 1 },
            e1RMTrendByExercise: [:],
            intensity: .empty,
            avgRPE: nil,
            daysSinceLastSession: 2,
            totalWorkingSets: max(1, Int(sets.values.reduce(0, +).rounded(.up))),
            allTimeWorkingSets: allTimeSets ?? max(1, Int(sets.values.reduce(0, +).rounded(.up))),
            goal: .strength,
            experience: .intermediate)
    }

    private func coachFacts(now: Date,
                            completedSets: [BodyPart: Double],
                            strengthDays: Int,
                            cardioDays: Int = 0,
                            recovery: RecoveryState = .empty) -> CoachFacts {
        let balance = WeeklyBalance(
            strengthDays: strengthDays,
            cardioDays: cardioDays,
            patternsTrained: [],
            bodyPartsTrained: Set(completedSets.keys),
            fractionalSets: completedSets,
            moderateMinutes: Double(cardioDays * 35),
            vigorousMinutes: 0,
            moderateEquivalentMinutes: Double(cardioDays * 35),
            hardDays: strengthDays,
            consecutiveHardDays: 0,
            vo2maxLatest: nil,
            vo2maxProtocol: nil,
            vo2maxTrend: nil,
            readinessAvailable: false,
            dataCompleteness: .moderate)
        return CoachFacts(
            events: [],
            recovery: recovery,
            weeklyBalance: balance,
            goal: .strength,
            experience: .intermediate,
            referenceDate: now,
            rolling72hCompletedEvents: [],
            rolling7dCompletedEvents: [],
            rolling28dCompletedEvents: [])
    }

    private func weeklyPlan(now: Date,
                            days: [(offset: Int, kinds: [CoachSessionKind])]) -> WeeklyPlan {
        let cal = Calendar.current
        let outlines = days.map { row -> WeeklyPlan.DayOutline in
            let date = cal.date(byAdding: .day, value: row.offset, to: now) ?? now
            let sessions = row.kinds.map { kind in
                PlannedSession(
                    id: "test-\(row.offset)-\(kind.rawValue)",
                    kind: kind,
                    label: kind.rawValue,
                    isHard: kind == .strength || kind == .vo2Intervals,
                    isRest: kind == .rest)
            }
            return WeeklyPlan.DayOutline(
                date: date,
                label: sessions.map(\.label).joined(separator: " · "),
                sessions: sessions,
                isFuture: true)
        }
        return WeeklyPlan(days: outlines, generatedAt: now)
    }

    private func genericStrengthSession() -> CoachSession {
        CoachSession(
            id: "strength.generic",
            kind: .strength,
            title: "Strength session",
            subtitle: "Generic full body",
            durationMinutes: 45,
            exercises: [
                .init(name: "Back Squat", sets: 3),
                .init(name: "Bench Press", sets: 3),
                .init(name: "Barbell Row", sets: 3),
                .init(name: "Romanian Deadlift", sets: 3),
            ],
            trainingLoadTags: ["strength"],
            citationIds: ["schoenfeld2021"],
            launchPayload: .strengthPlan("fullBody"),
            systemsTrained: [.maximalStrength, .hypertrophy],
            evidenceCategory: .strengthIntensity)
    }

    private func makeDayOutline(date: Date, kinds: [CoachSessionKind], cal: Calendar) -> WeeklyPlan.DayOutline {
        let sessions = kinds.enumerated().map { i, kind in
            PlannedSession(
                id: "test-\(i)-\(kind.rawValue)",
                kind: kind,
                label: kind.rawValue,
                isHard: kind == .strength || kind == .vo2Intervals,
                isRest: kind == .rest)
        }
        return WeeklyPlan.DayOutline(
            date: date,
            label: sessions.map(\.label).joined(separator: " · "),
            sessions: sessions,
            isFuture: true)
    }
}
