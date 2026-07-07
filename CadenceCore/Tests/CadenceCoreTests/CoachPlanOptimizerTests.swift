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

        XCTAssertEqual(optimized.plannedStrengthSessions.count, 1)
        XCTAssertTrue(optimized.unresolvedDeficits.isEmpty)
        let names = optimized.plannedStrengthSessions.flatMap { $0.exercises ?? [] }.map(\.name)
        XCTAssertTrue(names.contains("Bench Press"))
        XCTAssertTrue(names.contains("Overhead Press"))

        let insights = PlanAwareInsightEngine.run(
            completed: facts,
            plan: plan,
            plannedStrengthSessions: optimized.plannedStrengthSessions,
            unresolvedDeficits: optimized.unresolvedDeficits,
            diagnostics: optimized.diagnostics,
            now: now)

        XCTAssertNil(lowVolumeInsight(.chest, in: insights))
        XCTAssertNil(lowVolumeInsight(.shoulders, in: insights))
        XCTAssertNil(lowVolumeInsight(.triceps, in: insights))
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

        XCTAssertEqual(optimized.plannedStrengthSessions.count, 2)
        XCTAssertNotEqual(optimized.plannedStrengthSessions, [generic, generic])
        XCTAssertTrue(optimized.plannedStrengthSessions.first?.exercises?.contains {
            $0.name == "Overhead Press"
        } ?? false)
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

    /// Reproduces the "coach paints itself into a corner" bug (Phase 3):
    /// User starts Monday with a coach-planned workout covering chest/back/legs/
    /// shoulders + minimal arm work. After completing it, the base engine flags abs
    /// and calves as "low volume." The plan-aware layer should not surface individual
    /// low-volume attention alerts for body parts the remaining week cannot cover —
    /// the user's scenario: abs & calves had 0 sets, biceps & triceps were underdone.
    func testMondayPostWorkoutSuppressesUntrainedPartAlertsWhenWeekIsTight() {
        let cal = Calendar(identifier: .gregorian)
        var mondayComps = DateComponents()
        mondayComps.calendar = cal
        mondayComps.year = 2026; mondayComps.month = 6; mondayComps.day = 22  // Monday
        mondayComps.hour = 18   // evening, post-workout
        let now = mondayComps.date ?? Date(timeIntervalSince1970: 1_782_300_000)

        // Monday workout: 2 sets each of chest/back/legs/shoulders, 1 set biceps/triceps.
        // Abs and calves — zero sets. The optimizer sees biceps/triceps as containing
        // some volume but below MEV, so it tries to fill them. But abs/calves at 0
        // are NOT chased (by design). The base engine STILL flags them as "low volume."
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

        // BUG REPRODUCTION: individual "low volume" attention insights for
        // abs and calves should NOT appear when the optimizer cannot cover them
        // (they had 0 sets so they're not in lowVolumeAttentionParts, but the
        // base engine still flags them). The plan-aware layer should suppress
        // these when we're early in the week with remaining slots that are
        // already committed to other deficits.
        let individualLowVolume = insights.filter {
            $0.kind == .volume
                && $0.severity == .attention
                && $0.title.localizedCaseInsensitiveContains("low")
                && $0.part != nil
        }

        // If the optimizer can't resolve everything, suppress individual alerts
        // for parts with 0 completed sets — the user can't act on them.
        let untrainedPartsWithAlerts = individualLowVolume.filter { ins in
            guard let part = ins.part else { return false }
            return (completedSets[part] ?? 0) == 0
        }
        XCTAssertTrue(untrainedPartsWithAlerts.isEmpty,
                      "Should not show individual low-volume alerts for untrained parts (0 completed sets) when week is tight, but got: \(untrainedPartsWithAlerts.map { $0.part?.rawValue ?? "nil" })")

        // If an unresolved planning insight exists, ensure it's the ONLY volume attention.
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

    private func trainingFacts(_ sets: [BodyPart: Double]) -> TrainingFacts {
        TrainingFacts(
            weeklySetsByPart: sets,
            frequencyByPart: sets.mapValues { _ in 1 },
            e1RMTrendByExercise: [:],
            intensity: .empty,
            avgRPE: nil,
            daysSinceLastSession: 2,
            totalWorkingSets: max(1, Int(sets.values.reduce(0, +).rounded(.up))),
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
