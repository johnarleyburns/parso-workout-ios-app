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
}
