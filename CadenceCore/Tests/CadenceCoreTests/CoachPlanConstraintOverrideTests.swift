import XCTest
@testable import CadenceCore

/// The "I missed a day — ignore constraints and plan workouts to meet my weekly
/// deficits" override. Under the default `.safe` policy the coach refuses to plan
/// back-to-back hard days, oversized sessions, work on rest days, or work while
/// recovery is still open — so a crunched week leaves volume deficits unresolved.
/// The `.meetDeficits` policy relaxes those guardrails so the deficits close.
final class CoachPlanConstraintOverrideTests: XCTestCase {

    func testSafePolicyLeavesDeficitsWhenRecoveryAndRestBlockTheWeek() {
        let now = fixedWednesday()
        let facts = trainingFacts([.chest: 2, .shoulders: 2, .triceps: 1])
        let plan = crunchedWeek(now: now)

        let safe = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: blockedCoachFacts(now: now, facts: facts),
            weeklyPlan: plan,
            schedulePreferences: preferences(),
            candidates: [genericStrengthSession()],
            constraintPolicy: .safe)

        // Every remaining strength slot is recovery-blocked and the other days are
        // rest days, so the safe planner cannot place any work.
        XCTAssertTrue(safe.plannedStrengthSessions.isEmpty,
                      "Safe policy must not plan through recovery/rest constraints")
        XCTAssertFalse(safe.unresolvedDeficits.isEmpty,
                       "Safe policy should leave the week's deficits unresolved")
        XCTAssertTrue(safe.diagnostics.contains { $0.kind == .recoveryBlocked })
    }

    func testMeetDeficitsOverrideClosesTheDeficits() {
        let now = fixedWednesday()
        let facts = trainingFacts([.chest: 2, .shoulders: 2, .triceps: 1])
        let plan = crunchedWeek(now: now)

        let override = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: blockedCoachFacts(now: now, facts: facts),
            weeklyPlan: plan,
            schedulePreferences: preferences(),
            candidates: [genericStrengthSession()],
            constraintPolicy: .meetDeficits)

        XCTAssertFalse(override.plannedStrengthSessions.isEmpty,
                       "Override must plan work even when recovery/rest would block it")
        XCTAssertTrue(override.unresolvedDeficits.isEmpty,
                      "Override should close the week's volume deficits: \(override.unresolvedDeficits)")
    }

    func testOverridePlansMoreThanSafeForTheSameWeek() {
        let now = fixedWednesday()
        let facts = trainingFacts([.chest: 2, .shoulders: 2, .triceps: 1])
        let plan = crunchedWeek(now: now)
        let coach = blockedCoachFacts(now: now, facts: facts)

        let safe = CoachPlanOptimizer.optimize(
            trainingFacts: facts, coachFacts: coach, weeklyPlan: plan,
            schedulePreferences: preferences(), candidates: [genericStrengthSession()],
            constraintPolicy: .safe)
        let override = CoachPlanOptimizer.optimize(
            trainingFacts: facts, coachFacts: coach, weeklyPlan: plan,
            schedulePreferences: preferences(), candidates: [genericStrengthSession()],
            constraintPolicy: .meetDeficits)

        XCTAssertGreaterThan(override.plannedStrengthSessions.count,
                             safe.plannedStrengthSessions.count,
                             "Override should schedule more sessions than the safe plan")
        // It closed the deficit by using days the safe planner refused (rest /
        // recovery-blocked / back-to-back), i.e. more than the single planned slot.
        XCTAssertGreaterThanOrEqual(override.plannedStrengthSessions.count, 2)
    }

    func testOverrideRelaxesSessionSizeToCloseMoreInOneDay() {
        let now = fixedWednesday()
        // Whole-body hole with only a single available day: the safe per-session
        // caps (5 exercises / 16 sets) can't cover every part in one session; the
        // override's larger caps can.
        let facts = trainingFacts([
            .legs: 2, .back: 2, .chest: 2, .shoulders: 2,
            .biceps: 2, .triceps: 2, .calves: 2, .abs: 2,
        ])
        let plan = weeklyPlan(now: now, days: [(1, [.strength])])
        let coach = coachFacts(now: now, completedSets: facts.weeklySetsByPart, strengthDays: 0)

        let safe = CoachPlanOptimizer.optimize(
            trainingFacts: facts, coachFacts: coach, weeklyPlan: plan,
            schedulePreferences: preferences(), candidates: [genericStrengthSession()],
            constraintPolicy: .safe)
        let override = CoachPlanOptimizer.optimize(
            trainingFacts: facts, coachFacts: coach, weeklyPlan: plan,
            schedulePreferences: preferences(), candidates: [genericStrengthSession()],
            constraintPolicy: .meetDeficits)

        let safeRemaining = safe.unresolvedDeficits.values.reduce(0, +)
        let overrideRemaining = override.unresolvedDeficits.values.reduce(0, +)
        XCTAssertLessThan(overrideRemaining, safeRemaining,
                          "Override should close more total volume in one day than safe")

        let safeExercises = safe.plannedStrengthSessions.flatMap { $0.exercises ?? [] }.count
        let overrideExercises = override.plannedStrengthSessions.flatMap { $0.exercises ?? [] }.count
        XCTAssertGreaterThan(overrideExercises, safeExercises,
                             "Override should fit more exercises into the single session")
    }

    func testSafePolicyRemainsTheDefault() {
        let now = fixedWednesday()
        let facts = trainingFacts([.chest: 2, .shoulders: 2, .triceps: 1])
        let plan = crunchedWeek(now: now)
        let coach = blockedCoachFacts(now: now, facts: facts)

        let explicitSafe = CoachPlanOptimizer.optimize(
            trainingFacts: facts, coachFacts: coach, weeklyPlan: plan,
            schedulePreferences: preferences(), candidates: [genericStrengthSession()],
            constraintPolicy: .safe)
        let defaulted = CoachPlanOptimizer.optimize(
            trainingFacts: facts, coachFacts: coach, weeklyPlan: plan,
            schedulePreferences: preferences(), candidates: [genericStrengthSession()])

        XCTAssertEqual(defaulted, explicitSafe,
                       "Omitting constraintPolicy must behave exactly like .safe")
    }

    // MARK: - Fixtures

    /// It's Wednesday; the only planned strength day is tomorrow (inside the open
    /// whole-body recovery window) and the remaining days are rest days.
    private func crunchedWeek(now: Date) -> WeeklyPlan {
        weeklyPlan(now: now, days: [
            (1, [.strength]),
            (2, [.rest]),
            (3, [.rest]),
            (4, [.rest]),
        ])
    }

    /// Whole-body recovery open for two more days, so tomorrow's strength slot is
    /// not hard-eligible under the safe policy.
    private func blockedCoachFacts(now: Date, facts: TrainingFacts) -> CoachFacts {
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
        return coachFacts(now: now, completedSets: facts.weeklySetsByPart,
                          strengthDays: 1, recovery: recovery)
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

    private func preferences() -> CoachSchedulePreferences {
        CoachSchedulePreferences(
            strengthDaysPerWeek: 2,
            cardioDaysPerWeek: 3,
            restPreference: .fixed(days: []),
            allowsTwoADays: false)
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
