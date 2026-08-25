import XCTest
@testable import CadenceCore

/// Phase 6 regressions for the `BodyPart` → `MuscleGroup` migration: the optimizer
/// now plans against 20 named groups instead of 8 coarse body parts, and these
/// tests pin the three properties that change had to preserve — a bounded
/// candidate universe, a bounded session size, and group-level recovery gating.
final class CoachPlanOptimizerMuscleGroupTests: XCTestCase {

    /// The candidate universe is the user's tracked groups, never all 20. Without
    /// this the optimizer chases `tibialis`, `neck` and `rotatorCuff` — groups the
    /// catalog has no depth behind, so their deficits could never close (D4).
    func testOptimizerOnlyTargetsTrackedGroups() {
        let now = fixedWednesday()
        let facts = trainingFacts([:])   // cold start: everything is a deficit
        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coachFacts(now: now),
            weeklyPlan: weeklyPlan(now: now, days: [(1, [.strength]), (3, [.strength])]),
            schedulePreferences: preferences(),
            candidates: [genericStrengthSession()])

        let untracked = MuscleGroup.canonicalOrder.filter { !$0.isTrackedByDefault }
        for group in untracked {
            XCTAssertNil(optimized.unresolvedDeficits[group],
                         "\(group.displayName) is untracked and must never carry a deficit")
        }
        XCTAssertTrue(optimized.unresolvedDeficits.keys.allSatisfy(\.isTrackedByDefault),
                      "Every reported deficit must belong to a tracked group")
    }

    /// 13 tracked dimensions instead of 8 must not make sessions longer: the policy
    /// caps exercises and total sets, and a cold-start plan has to respect it.
    func testSessionExerciseCountDoesNotGrowVersusEightPartBaseline() {
        let now = fixedWednesday()
        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: trainingFacts([:]),
            coachFacts: coachFacts(now: now),
            weeklyPlan: weeklyPlan(now: now, days: [(1, [.strength]), (3, [.strength])]),
            schedulePreferences: preferences(),
            candidates: [genericStrengthSession()])

        XCTAssertFalse(optimized.plannedStrengthSessions.isEmpty, "expected a planned session")
        for session in optimized.plannedStrengthSessions {
            let exercises = session.exercises ?? []
            XCTAssertLessThanOrEqual(exercises.count,
                                     PlanningConstraintPolicy.safe.maxExercisesPerSession,
                                     "\(session.title) grew past the per-session exercise cap")
            let sets = exercises.reduce(0) { $0 + ($1.sets ?? 0) }
            XCTAssertLessThanOrEqual(sets, PlanningConstraintPolicy.safe.maxTotalSetsPerSession,
                                     "\(session.title) grew past the per-session set cap")
        }
    }

    /// Upper/lower classification reads the 20-group vocabulary: every lower-body
    /// group (not just the retired `.legs`/`.calves` pair) counts as lower, and
    /// abdominals stay neutral so a leg day is not misread as full-body.
    func testUpperLowerSplitAssignsGroupsCorrectly() {
        let lower = strengthSession(named: "Lower", exercises: [
            .init(name: "Back Squat", primaryMuscles: ["quadriceps"], sets: 3),
            .init(name: "Romanian Deadlift", primaryMuscles: ["hamstrings"], sets: 3),
            .init(name: "Standing Calf Raise", primaryMuscles: ["calves"], sets: 3),
        ])
        XCTAssertEqual(CoachPlanOptimizer.classifyStructure(of: lower), .lowerFocus,
                       "Quads/hamstrings/calves is a lower-body session")

        let upper = strengthSession(named: "Upper", exercises: [
            .init(name: "Bench Press", primaryMuscles: ["chest"], sets: 3),
            .init(name: "Barbell Row", primaryMuscles: ["middle back"], sets: 3),
        ])
        XCTAssertEqual(CoachPlanOptimizer.classifyStructure(of: upper), .upperFocus,
                       "Chest and upper back with no leg work is an upper-body session")

        let coreOnly = strengthSession(named: "Core", exercises: [
            .init(name: "Cable Crunch", primaryMuscles: ["abdominals"], sets: 3),
        ])
        XCTAssertEqual(CoachPlanOptimizer.classifyStructure(of: coreOnly), .focused,
                       "Abdominals are neither upper nor lower, so a core day is focused")
    }

    /// Hard-recovery windows are keyed by muscle group. A quadriceps window still
    /// standing must keep a squat out of today's plan.
    func testRecoveryGatingUsesGroupWindows() {
        let now = fixedWednesday()
        let blocked = RecoveryWindow(lastExposedAt: now.addingTimeInterval(-3600),
                                     hardEligibleAt: now.addingTimeInterval(72 * 3600),
                                     reason: .muscleGroup,
                                     confidence: .high)
        let recovery = RecoveryState(byExercise: [:], byPattern: [:],
                                     byGroup: [.quadriceps: blocked], wholeBody: nil)

        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: trainingFacts([:]),
            coachFacts: coachFacts(now: now, recovery: recovery),
            weeklyPlan: weeklyPlan(now: now, days: [(1, [.strength])]),
            schedulePreferences: preferences(),
            candidates: [genericStrengthSession()])

        let planned = optimized.plannedStrengthSessions.flatMap { $0.exercises ?? [] }
        XCTAssertFalse(planned.contains { $0.name == "Back Squat" },
                       "A standing quadriceps recovery window must gate direct quad work")
        XCTAssertFalse(planned.isEmpty,
                       "The rest of the body is still trainable — the coach suggests, it does not cancel")
    }

    // MARK: - Helpers

    private func fixedWednesday() -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 8
        comps.day = 26
        comps.hour = 12
        return comps.date ?? Date(timeIntervalSince1970: 1_782_300_000)
    }

    private func preferences() -> CoachSchedulePreferences {
        CoachSchedulePreferences(strengthDaysPerWeek: 2,
                                 cardioDaysPerWeek: 3,
                                 restPreference: .fixed(days: []),
                                 allowsTwoADays: false)
    }

    private func trainingFacts(_ sets: [MuscleGroup: Double]) -> TrainingFacts {
        TrainingFacts(
            weeklySetsByGroup: sets,
            frequencyByGroup: sets.mapValues { _ in 1 },
            e1RMTrendByExercise: [:],
            intensity: .empty,
            avgRPE: nil,
            daysSinceLastSession: 2,
            totalWorkingSets: max(1, Int(sets.values.reduce(0, +).rounded(.up))),
            allTimeWorkingSets: max(1, Int(sets.values.reduce(0, +).rounded(.up))),
            goal: .strength,
            experience: .intermediate)
    }

    private func coachFacts(now: Date, recovery: RecoveryState = .empty) -> CoachFacts {
        let balance = WeeklyBalance(
            strengthDays: 0,
            cardioDays: 0,
            patternsTrained: [],
            muscleGroupsTrained: [],
            fractionalSets: [:],
            moderateMinutes: 0,
            vigorousMinutes: 0,
            moderateEquivalentMinutes: 0,
            hardDays: 0,
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
                PlannedSession(id: "mg-\(row.offset)-\(kind.rawValue)",
                               kind: kind,
                               label: kind.rawValue,
                               isHard: kind == .strength,
                               isRest: kind == .rest)
            }
            return WeeklyPlan.DayOutline(date: date,
                                         label: sessions.map(\.label).joined(separator: " · "),
                                         sessions: sessions,
                                         isFuture: true)
        }
        return WeeklyPlan(days: outlines, generatedAt: now)
    }

    private func strengthSession(named name: String,
                                 exercises: [CoachSession.RecommendedExercise]) -> CoachSession {
        CoachSession(id: "structure.\(name)",
                     kind: .strength,
                     title: name,
                     durationMinutes: 45,
                     exercises: exercises,
                     trainingLoadTags: ["strength"],
                     citationIds: ["schoenfeld2021"],
                     launchPayload: .strengthPlan(name))
    }

    private func genericStrengthSession() -> CoachSession {
        CoachSession(id: "strength.generic",
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
                     launchPayload: .strengthPlan("fullBody"))
    }
}
