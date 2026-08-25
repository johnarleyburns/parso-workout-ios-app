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
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByGroup, strengthDays: 1, cardioDays: 2)
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

        // Genuinely unresolved deficits surface via the aggregate triage only
        // (partial when planned work closed some parts, unresolved when none).
        if !optimized.unresolvedDeficits.isEmpty {
            XCTAssertNotNil(aggregatePlanningShortfall(in: insights))
        }
    }

    func testOptimizerDoesNotBlindlyRepeatGenericFallbackForFutureStrengthSlots() {
        let now = fixedWednesday()
        let facts = trainingFacts([
            .chest: 4,
            .shoulders: 2,
            .triceps: 2,
        ])
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByGroup, strengthDays: 0)
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

    func testOptimizerUsesDesiredSetsWhenCandidateSetsAreMissing() throws {
        let now = fixedWednesday()
        let facts = trainingFacts([.chest: 0])
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByGroup, strengthDays: 0)
        let plan = weeklyPlan(now: now, days: [(1, [.strength])])
        let prefs = CoachSchedulePreferences(
            strengthDaysPerWeek: 2,
            cardioDaysPerWeek: 3,
            restPreference: .fixed(days: []),
            allowsTwoADays: false,
            desiredSetsPerExercise: 4,
            trackedMuscleGroups: [.chest]
        )
        let candidate = CoachSession(
            id: "strength.nilSets",
            kind: .strength,
            title: "Strength session",
            exercises: [.init(name: "Bench Press")],
            launchPayload: .strengthPlan("nilSets")
        )

        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: plan,
            schedulePreferences: prefs,
            candidates: [candidate])

        let exercise = try XCTUnwrap(
            optimized.plannedStrengthSessions
                .flatMap { $0.exercises ?? [] }
                .first { $0.name == "Bench Press" }
        )
        XCTAssertEqual(exercise.sets, 4)
        XCTAssertEqual(exercise.repLadder, [5, 5, 3, 3])
    }

    func testOptimizerTargetsOnlyRemainingLowGroups() {
        let now = fixedWednesday()
        let facts = trainingFacts(trackedSets(baseline: 12, [
            .abdominals: 9, .biceps: 0, .triceps: 0, .calves: 0,
        ]))
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByGroup, strengthDays: 1)
        let plan = weeklyPlan(now: now, days: [(1, [.strength])])

        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: plan,
            schedulePreferences: preferences(twoADays: false),
            candidates: [genericStrengthSession()])

        let names = Set(optimized.plannedStrengthSessions.flatMap { $0.exercises ?? [] }.map(\.name))
        XCTAssertTrue(names.contains("Barbell Curl"), "Biceps deficit should select direct biceps work")
        XCTAssertTrue(names.contains("Triceps Pushdown"), "Triceps deficit should select direct triceps work")
        XCTAssertTrue(names.contains("Standing Calf Raise"), "Calves deficit should select direct calf work")
        XCTAssertFalse(names.contains("Back Squat"), "Satisfied legs should not drive the recommendation")
        XCTAssertFalse(names.contains("Bench Press"), "Satisfied chest should not drive the recommendation")
        XCTAssertFalse(names.contains("Romanian Deadlift"), "Satisfied back/legs should not drive the recommendation")
    }

    func testOptimizerCarriesHistoryBasedSuggestedWeightIntoPlan() throws {
        let now = fixedWednesday()
        let snapshot = LiftSnapshot(exercise: "Bench Press", group: .chest,
                                    topSetWeightKg: 80, topSetReps: 5,
                                    bestE1RM: 93.333, trend: nil)
        var facts = trainingFacts(trackedSets(baseline: 14, [.chest: 0]))
        facts = TrainingFacts(
            weeklySetsByGroup: facts.weeklySetsByGroup,
            frequencyByGroup: facts.frequencyByGroup,
            e1RMTrendByExercise: facts.e1RMTrendByExercise,
            intensity: facts.intensity,
            avgRPE: facts.avgRPE,
            daysSinceLastSession: facts.daysSinceLastSession,
            totalWorkingSets: facts.totalWorkingSets,
            allTimeWorkingSets: facts.allTimeWorkingSets,
            liftSnapshots: ["Bench Press": snapshot],
            goal: facts.goal,
            experience: facts.experience)
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByGroup, strengthDays: 0)
        let plan = weeklyPlan(now: now, days: [(1, [.strength])])
        let candidate = CoachSession(
            id: "strength.bench", kind: .strength, title: "Bench",
            exercises: [.init(name: "Bench Press", sets: 3, repsLow: 8, repsHigh: 10)],
            launchPayload: .strengthPlan("bench"))

        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: plan,
            schedulePreferences: preferences(twoADays: false),
            candidates: [candidate])
        let exercise = try XCTUnwrap(optimized.plannedStrengthSessions.first?.exercises?.first)
        XCTAssertNotNil(exercise.loadKg)
        XCTAssertGreaterThan(exercise.loadKg ?? 0, 0)
    }

    func testImpossibleCaseEmitsOneUnresolvedPlanningInsight() {
        let now = fixedWednesday()
        let facts = trainingFacts([
            .quadriceps: 1,
            .lats: 1,
            .chest: 1,
            .shoulders: 1,
            .biceps: 1,
            .triceps: 1,
            .calves: 1,
            .abdominals: 1,
        ])
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByGroup, strengthDays: 1)
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

        XCTAssertEqual(insights.filter {
            $0.id == "planning.partialResolved" || $0.id == "planning.unresolvedVolume"
        }.count, 1)
        let individualLowVolume = insights.filter {
            $0.kind == .volume
                && $0.severity == .attention
                && $0.title.localizedCaseInsensitiveContains("low")
                && $0.group != nil
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
        let completedSets: [MuscleGroup: Double] = [
            .chest: 2, .lats: 2, .quadriceps: 2, .shoulders: 2,
            .biceps: 1, .triceps: 1,
            .abdominals: 0, .calves: 0,
        ]
        let facts = TrainingFacts(
            weeklySetsByGroup: completedSets,
            frequencyByGroup: completedSets.compactMapValues { $0 > 0 ? 1 : nil },
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
            muscleGroupsTrained: Set(completedSets.keys).filter { completedSets[$0] ?? 0 > 0 },
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
                && $0.group != nil
        }

        let untrainedPartsWithAlerts = individualLowVolume.filter { ins in
            guard let part = ins.group else { return false }
            return (completedSets[part] ?? 0) == 0
        }
        XCTAssertTrue(untrainedPartsWithAlerts.isEmpty,
                      "Should not show individual low-volume alerts for untrained parts (0 completed sets), but got: \(untrainedPartsWithAlerts.map { $0.group?.rawValue ?? "nil" })")

        // For any genuine unresolved deficits, the aggregate triage insight exists.
        if !optimized.unresolvedDeficits.isEmpty {
            XCTAssertNotNil(aggregatePlanningShortfall(in: insights),
                            "Expected an aggregate planning insight when deficits exist")
        }
    }

    func testOptimizerOutputIsDeterministic() {
        let now = fixedWednesday()
        let facts = trainingFacts([
            .chest: 4,
            .shoulders: 2,
            .triceps: 2,
        ])
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByGroup, strengthDays: 1)
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
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByGroup, strengthDays: 1)
        let cardioOnlyPlan = weeklyPlan(now: now, days: [
            (1, [.moderateAerobic]),
        ])

        // Phase 3: the plan has no eligible strength slot, but today (Wednesday) is
        // a free, non-rest, recovery-eligible day with a genuine weekly strength
        // shortfall — so the coach self-schedules a single ad-hoc session today. The
        // cardio sits on Thursday, so this is NOT a two-a-day even with two-a-days off.
        let noTwoADays = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: cardioOnlyPlan,
            schedulePreferences: preferences(twoADays: false),
            candidates: [genericStrengthSession()])
        XCTAssertEqual(noTwoADays.plannedStrengthSessions.count, 1)
        XCTAssertTrue(noTwoADays.diagnostics.contains { $0.id == "plannedExistingSlot.today.adhoc" },
                      "Coach self-schedules the free day today rather than doubling up on the cardio day")

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
        // The only planned strength slot lands on the user's fixed rest day (Thursday),
        // so the coach must skip it — but it may self-schedule today (not a rest day)
        // to close the weekly shortfall.
        XCTAssertTrue(fixedRest.diagnostics.contains { $0.kind == .recoveryBlocked },
                      "Coach must skip the strength slot that falls on the fixed rest day")
        XCTAssertEqual(fixedRest.plannedStrengthSessions.count, 1)
        XCTAssertTrue(fixedRest.diagnostics.contains { $0.id == "plannedExistingSlot.today.adhoc" },
                      "Coach self-schedules today rather than training the fixed rest day")

        let recoveryEnd = Calendar.current.date(byAdding: .day, value: 2, to: now) ?? now
        let recovery = RecoveryState(
            byExercise: [:],
            byPattern: [:],
            byGroup: [:],
            wholeBody: RecoveryWindow(
                lastExposedAt: now,
                hardEligibleAt: recoveryEnd,
                reason: .fatigue,
                confidence: .moderate))
        let recoveryBlocked = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coachFacts(now: now, completedSets: facts.weeklySetsByGroup,
                                   strengthDays: 1, recovery: recovery),
            weeklyPlan: fixedRestPlan,
            schedulePreferences: preferences(twoADays: true),
            candidates: [genericStrengthSession()])
        XCTAssertTrue(recoveryBlocked.plannedStrengthSessions.isEmpty)
        XCTAssertTrue(recoveryBlocked.diagnostics.contains { $0.kind == .recoveryBlocked })
    }

    /// Guard for the ad-hoc "route residual volume into today" slot (Phase 3): it
    /// closes a genuine weekly strength shortfall on a free day, but must never
    /// manufacture a two-a-day the user disallowed. When today already holds a
    /// (cardio) session and two-a-days are off, the coach defers to the aggregate
    /// nag instead of stacking a second session; with two-a-days on, it may add it.
    func testAdHocTodaySlotRespectsTwoADayPreference() {
        let now = fixedWednesday()
        let facts = trainingFacts([.chest: 2, .shoulders: 2, .triceps: 1])
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByGroup,
                               strengthDays: 0, cardioDays: 1)
        // Today (Wednesday) already holds a cardio session; no strength slots exist.
        let cardioTodayPlan = weeklyPlan(now: now, days: [
            (0, [.moderateAerobic]),
        ])

        let noTwoADays = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: cardioTodayPlan,
            schedulePreferences: preferences(twoADays: false),
            candidates: [genericStrengthSession()])
        XCTAssertTrue(noTwoADays.plannedStrengthSessions.isEmpty,
                      "Ad-hoc today slot must not create a two-a-day when the user disallows them")

        let twoADays = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: cardioTodayPlan,
            schedulePreferences: preferences(twoADays: true),
            candidates: [genericStrengthSession()])
        XCTAssertTrue(twoADays.diagnostics.contains { $0.id == "plannedExistingSlot.today.adhoc" },
                      "With two-a-days allowed the coach may self-schedule strength today")
    }

    /// The ad-hoc today slot only fires to close a genuine weekly shortfall. When
    /// every part is already at/above MEV there is nothing to route, so the coach
    /// plans nothing rather than inventing a session on a free day.
    func testAdHocTodaySlotSkippedWhenNoWeeklyShortfall() {
        let now = fixedWednesday()
        let facts = trainingFacts(trackedSets(baseline: 16, [
            .biceps: 14, .triceps: 14, .calves: 12, .abdominals: 12,
        ]))
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByGroup, strengthDays: 3)
        let emptyPlan = weeklyPlan(now: now, days: [])

        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: emptyPlan,
            schedulePreferences: preferences(twoADays: true),
            candidates: [genericStrengthSession()])
        XCTAssertTrue(optimized.plannedStrengthSessions.isEmpty,
                      "No ad-hoc session should be self-scheduled when there is no weekly shortfall")
    }

    func testTuesdayNoNagForAbsCalvesWhenPlanCoversWholeBody() {
        let cal = Calendar(identifier: .gregorian)
        var tuesdayComps = DateComponents()
        tuesdayComps.calendar = cal
        tuesdayComps.year = 2026; tuesdayComps.month = 6; tuesdayComps.day = 23 // Tuesday
        tuesdayComps.hour = 8  // morning, before any workout
        let now = tuesdayComps.date ?? Date(timeIntervalSince1970: 1_782_300_000)

        // Monday was logged: the big groups are already at a productive dose.
        // Abs and calves = 0 sets because the coach never planned them, so they are
        // the standing deficits going into the two remaining slots.
        let completedSets = trackedSets(baseline: 12, [.abdominals: 0, .calves: 0])
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
        XCTAssertNil(lowVolumeInsight(.abdominals, in: insights),
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

        // If capacity truly can't reach MEV, we should see the aggregate shortfall
        // triage (partial or unresolved), never per-part "low" nags.
        if !optimized.unresolvedDeficits.isEmpty {
            XCTAssertNotNil(aggregatePlanningShortfall(in: insights),
                            "Expected the aggregate planning shortfall insight when deficits remain")
            let untrainedPartsWithAlerts = insights.filter {
                $0.kind == .volume && $0.severity == .attention
                    && $0.title.localizedCaseInsensitiveContains("low")
                    && (completedSets[$0.group ?? .abdominals] ?? 0) == 0
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
        let facts = trainingFacts(trackedSets(baseline: 16, [
            .biceps: 14, .triceps: 14, .calves: 12, .abdominals: 3,
        ]))
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByGroup, strengthDays: 1)
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
            .plannedSetsByGroup(from: optimized.plannedStrengthSessions)[.abdominals] ?? 0
        let projectedAbs = 3 + plannedAbsSets
        let productive = VolumeLandmarks.productiveTarget(for: .abdominals, experience: .intermediate)
        XCTAssertEqual(productive, 9, "intermediate abs productive target is the MEV/MAV midpoint (6+12)/2 = 9")
        XCTAssertGreaterThanOrEqual(projectedAbs, productive,
            "Abs should be planned toward the productive dose (\(productive)), not the MEV floor — got projected \(projectedAbs)")
        // And there should be no residual below-MEV deficit for abs.
        XCTAssertNil(optimized.unresolvedDeficits[.abdominals],
                     "Abs trained to a productive dose leaves no below-MEV residual")
    }

    /// Guard: the productive target must never push a part above MRV.
    func testProductiveTargetNeverExceedsMRV() {        let now = fixedWednesday()
        let facts = trainingFacts([.abdominals: 3, .calves: 3])
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByGroup, strengthDays: 0)
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
            .plannedSetsByGroup(from: optimized.plannedStrengthSessions)
        for part in MuscleGroup.canonicalOrder {
            let total = (facts.weeklySetsByGroup[part] ?? 0) + (projected[part] ?? 0)
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
        let facts = trainingFacts(trackedSets(baseline: 16, [
            .biceps: 14, .triceps: 14, .calves: 12, .abdominals: 2,
        ]))
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByGroup, strengthDays: 1)
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

        XCTAssertNil(optimized.unresolvedDeficits[.abdominals],
                     "Abs planned to a productive dose leaves no below-MEV residual")
        XCTAssertNil(lowVolumeInsight(.abdominals, in: insights),
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

    /// The aggregate "weekly volume shortfall" triage insight. Phase 3 split the old
    /// single `planning.unresolvedVolume` into `planning.partialResolved` (some gaps
    /// closed by planned work, some still short) and `planning.unresolvedVolume`
    /// (nothing could be closed). Both are the `.attention`-level aggregate the coach
    /// surfaces in place of per-part nags, so tests assert on the family.
    private func aggregatePlanningShortfall(in insights: [Insight]) -> Insight? {
        insights.first { $0.id == "planning.partialResolved" || $0.id == "planning.unresolvedVolume" }
    }

    private func lowVolumeInsight(_ part: MuscleGroup, in insights: [Insight]) -> Insight? {
        insights.first {
            $0.kind == .volume
                && $0.group == part
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

    /// A weekly tally that covers every tracked group. DB++ tracks 13 groups, not
    /// the 8 retired body parts, so a test meaning "everything is satisfied except
    /// X" must say so explicitly — otherwise the eleven unnamed groups read as
    /// zero-volume deficits and out-rank the one the test is about.
    private func trackedSets(baseline: Double,
                             _ overrides: [MuscleGroup: Double] = [:]) -> [MuscleGroup: Double] {
        var out = Dictionary(uniqueKeysWithValues: MuscleGroup.defaultTracked.map { ($0, baseline) })
        for (group, value) in overrides { out[group] = value }
        return out
    }

    private func trainingFacts(_ sets: [MuscleGroup: Double],
                               allTimeSets: Int? = nil) -> TrainingFacts {
        TrainingFacts(
            weeklySetsByGroup: sets,
            frequencyByGroup: sets.mapValues { _ in 1 },
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
                            completedSets: [MuscleGroup: Double],
                            strengthDays: Int,
                            cardioDays: Int = 0,
                            recovery: RecoveryState = .empty,
                            events: [TrainingEvent] = []) -> CoachFacts {
        let balance = WeeklyBalance(
            strengthDays: strengthDays,
            cardioDays: cardioDays,
            patternsTrained: [],
            muscleGroupsTrained: Set(completedSets.keys),
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
            events: events,
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

    // MARK: - Planned load resolution (field test 2026-08-18 #2)

    /// A movement last trained three weeks ago is absent from `liftSnapshots`
    /// (trailing week only) and used to render as `BW×12`.
    func testPlannedLoadResolvesFromHistoryOlderThanOneWeek() {
        let now = fixedWednesday()
        let facts = trainingFacts([:])
        let coach = coachFacts(now: now, completedSets: [:], strengthDays: 0,
                               events: [strengthEvent("Standing Dumbbell Upright Row",
                                                      weightKg: 20, reps: 12, e1rm: 28,
                                                      daysAgo: 21, now: now)])
        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: weeklyPlan(now: now, days: [(1, [.strength])]),
            schedulePreferences: preferences(twoADays: false),
            candidates: [session(withExercises: ["Standing Dumbbell Upright Row"])])

        let planned = optimized.plannedStrengthSessions
            .flatMap { $0.exercises ?? [] }
            .first { $0.name == "Standing Dumbbell Upright Row" }
        XCTAssertNotNil(planned, "the planned session should still contain the movement")
        XCTAssertNotNil(planned?.loadKg,
                        "a lift trained 21 days ago must still carry a real load, not BW")
        XCTAssertGreaterThan(planned?.loadKg ?? 0, 0)
    }

    /// Anti-repeat rotation used to hard-code `loadKg: nil`, so every swapped-in
    /// isolation movement lost its weight.
    func testVarietyRotationKeepsAResolvedLoad() {
        let now = fixedWednesday()
        // Only the arms and the upper back are short, so the optimizer reaches for
        // the curl/row variants the history below prices.
        let facts = trainingFacts(trackedSets(baseline: 16, [
            .biceps: 0, .middleBack: 0,
        ]))
        // Both curl variants and both row variants are trained, so whichever the
        // day-2 rotation swaps in must still be priced. (Before the DB++ adoption
        // the coach put a curl on both days; rows credit the biceps indirectly now,
        // so it rotates a row variant instead — the defect under test is the same.)
        let history = ["Barbell Curl", "Dumbbell Curl", "Barbell Row", "Seated Cable Row"].map {
            strengthEvent($0, weightKg: 30, reps: 10, e1rm: 40, daysAgo: 12, now: now)
        }
        let coach = coachFacts(now: now, completedSets: [:], strengthDays: 0, events: history)
        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: weeklyPlan(now: now, days: [(1, [.strength]), (2, [.strength])]),
            schedulePreferences: preferences(twoADays: false),
            candidates: [session(withExercises: ["Barbell Curl"])])

        let all = optimized.plannedStrengthSessions.flatMap { $0.exercises ?? [] }
        let withHistory = all.filter {
            CoachSession.recentTopSet(forExerciseNamed: $0.name, facts: coach) != nil
        }
        // Day 2 rotates a trained movement out for a trained variant, so both must
        // be priced. Before the fix the rotated-in one was always nil.
        XCTAssertGreaterThanOrEqual(withHistory.count, 2,
                                    "rotation should have placed a second trained variant")
        for exercise in withHistory {
            XCTAssertNotNil(exercise.loadKg,
                            "\(exercise.name) has history, so the plan must carry its load")
        }
    }

    func testBodyweightMovementKeepsNilLoad() {
        let now = fixedWednesday()
        let coach = coachFacts(now: now, completedSets: [:], strengthDays: 0,
                               events: [strengthEvent("Push-Up", weightKg: 80, reps: 20, e1rm: 120,
                                                      daysAgo: 4, now: now)])
        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: trainingFacts([:]),
            coachFacts: coach,
            weeklyPlan: weeklyPlan(now: now, days: [(1, [.strength])]),
            schedulePreferences: preferences(twoADays: false),
            candidates: [session(withExercises: ["Push-Up"])])

        let pushUp = optimized.plannedStrengthSessions
            .flatMap { $0.exercises ?? [] }
            .first { $0.name == "Push-Up" }
        XCTAssertNil(pushUp?.loadKg, "a bodyweight movement must never be given an external load")
    }

    func testUntrainedLoadedMovementKeepsNilLoad() {
        let now = fixedWednesday()
        let coach = coachFacts(now: now, completedSets: [:], strengthDays: 0)
        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: trainingFacts([:]),
            coachFacts: coach,
            weeklyPlan: weeklyPlan(now: now, days: [(1, [.strength])]),
            schedulePreferences: preferences(twoADays: false),
            candidates: [session(withExercises: ["Standing Dumbbell Upright Row"])])

        let planned = optimized.plannedStrengthSessions
            .flatMap { $0.exercises ?? [] }
            .first { $0.name == "Standing Dumbbell Upright Row" }
        XCTAssertNil(planned?.loadKg, "we never invent a weight for a movement with no history")
    }

    /// The trailing-week snapshot still wins over the all-history fallback.
    func testTrailingWeekSnapshotStillWins() {
        let now = fixedWednesday()
        var facts = trainingFacts([:])
        facts = TrainingFacts(
            weeklySetsByGroup: facts.weeklySetsByGroup,
            frequencyByGroup: facts.frequencyByGroup,
            e1RMTrendByExercise: [:],
            intensity: .empty,
            avgRPE: nil,
            daysSinceLastSession: 2,
            totalWorkingSets: facts.totalWorkingSets,
            allTimeWorkingSets: facts.allTimeWorkingSets,
            liftSnapshots: ["Bench Press": LiftSnapshot(exercise: "Bench Press",
                                                        group: .chest,
                                                        topSetWeightKg: 100,
                                                        topSetReps: 5,
                                                        bestE1RM: 116,
                                                        trend: nil)],
            goal: .strength,
            experience: .intermediate)
        // Deliberately much lighter, much older history for the same lift.
        let coach = coachFacts(now: now, completedSets: [:], strengthDays: 0,
                               events: [strengthEvent("Bench Press", weightKg: 40, reps: 5, e1rm: 46,
                                                      daysAgo: 40, now: now)])
        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: weeklyPlan(now: now, days: [(1, [.strength])]),
            schedulePreferences: preferences(twoADays: false),
            candidates: [session(withExercises: ["Bench Press"])])

        let bench = optimized.plannedStrengthSessions
            .flatMap { $0.exercises ?? [] }
            .first { $0.name == "Bench Press" }
        XCTAssertNotNil(bench?.loadKg)
        XCTAssertGreaterThan(bench?.loadKg ?? 0, 60,
                             "the trailing-week snapshot (116 e1RM) must win over 40 kg from 40 days ago")
    }

    private func session(withExercises names: [String]) -> CoachSession {
        CoachSession(
            id: "strength.load",
            kind: .strength,
            title: "Strength session",
            subtitle: "Load resolution",
            durationMinutes: 45,
            exercises: names.map { .init(name: $0, sets: 3, repsLow: 8, repsHigh: 12) },
            trainingLoadTags: ["strength"],
            citationIds: ["schoenfeld2021"],
            launchPayload: .strengthPlan("fullBody"),
            systemsTrained: [.hypertrophy],
            evidenceCategory: .strengthIntensity)
    }

    private func strengthEvent(_ name: String,
                               weightKg: Double,
                               reps: Int,
                               e1rm: Double,
                               daysAgo: Int,
                               now: Date) -> TrainingEvent {
        let end = now.addingTimeInterval(-Double(daysAgo) * 86_400)
        let perExercise = StrengthEventDetails.PerExercise(
            exerciseID: name.lowercased(),
            exerciseName: name,
            patterns: [],
            muscleGroups: [],
            hardSetCount: 3,
            topSetWeightKg: weightKg,
            topSetReps: reps,
            bestE1RM: e1rm,
            meanRPE: 8,
            maxRPE: 9,
            reachedFailure: false,
            lastWorkingSetAt: end)
        return TrainingEvent(
            id: UUID(),
            start: end.addingTimeInterval(-3600),
            end: end,
            kind: .strength(StrengthEventDetails(exercises: [perExercise],
                                                 totalHardSets: 3,
                                                 duration: 3600,
                                                 sessionEnd: end)),
            source: .appStrength,
            completion: .completed)
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
