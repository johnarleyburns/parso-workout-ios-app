import XCTest
import SwiftData
@testable import CadenceCore

/// Regression coverage for "low reps prescribed for bodyweight/high-rep moves":
/// the coach must not stamp the goal's loaded 6–12 range onto crunches / air
/// squats. Bodyweight movements track the user's real logged reps, or default to
/// a high-rep range absent history; weighted lifts and time holds are unchanged.
final class CoachBodyweightPrescriptionTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private func fixedWednesday() -> Date {
        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.year = 2026; comps.month = 6; comps.day = 24; comps.hour = 12
        return comps.date ?? Date(timeIntervalSince1970: 1_782_300_000)
    }

    // MARK: - PrescriptionMath.repRange

    func testBodyweightWithHistoryTracksLoggedReps() {
        let range = PrescriptionMath.repRange(forExerciseNamed: "Crunch", goal: .hypertrophy,
                                              recentTopReps: 40)
        XCTAssertEqual(range.upperBound, 40, "top of the range tracks the user's real 40-rep set")
        XCTAssertGreaterThanOrEqual(range.lowerBound, 12, "range stays high-rep, never 6–12")
        XCTAssertNotEqual(range, TrainingGoal.hypertrophy.repRange)
    }

    func testBodyweightWithoutHistoryDefaultsToHighRep() {
        let range = PrescriptionMath.repRange(forExerciseNamed: "Air Squat", goal: .hypertrophy)
        XCTAssertEqual(range, 15...25, "a high-rep bodyweight move defaults to 15–25 absent history")
    }

    func testWeightedLiftKeepsGoalRangeEvenWithRepHistory() {
        let range = PrescriptionMath.repRange(forExerciseNamed: "Back Squat", goal: .hypertrophy,
                                              recentTopReps: 40)
        XCTAssertEqual(range, TrainingGoal.hypertrophy.repRange,
                       "weighted lifts keep the goal's loaded range; reps aren't the progression variable")
    }

    func testTimeHoldKeepsGoalRange() {
        XCTAssertEqual(PrescriptionMath.repRange(forExerciseNamed: "Plank", goal: .hypertrophy),
                       TrainingGoal.hypertrophy.repRange,
                       "time holds are unchanged (builders special-case them)")
    }

    func testStrengthBiasedBodyweightWithoutHistoryStaysConservative() {
        XCTAssertEqual(PrescriptionMath.repRange(forExerciseNamed: "Pull-Up", goal: .hypertrophy),
                       TrainingGoal.hypertrophy.repRange,
                       "pull-ups are bodyweight but low-rep — no aggressive 15–25 default without history")
    }

    // MARK: - End-to-end: planned session prescribes high reps for bodyweight history

    func testPlannedBodyweightExercisePrescribesHighReps() throws {
        let ctx = try makeContext()
        let now = fixedWednesday()

        // The user logs bodyweight crunches at 40 reps (load 0) ~10 days ago.
        let date = now.addingTimeInterval(-10 * 86400)
        let session = try WorkoutRepository.createSession(date: date, in: ctx)
        let crunch = try WorkoutRepository.findOrCreateExercise(
            named: "Crunch", primaryMuscles: ["abs"], in: ctx)
        for reps in [40, 30, 20, 10] {
            _ = try WorkoutRepository.addSet(to: session, exercise: crunch, weightKg: 0, reps: reps,
                                             usesBodyweight: true, completedAt: date, in: ctx)
        }
        session.endedAt = date.addingTimeInterval(1200)
        try ctx.save()
        let events = [TrainingEvent.from(session: session)!]

        let coach = CoachFacts.make(from: events, goal: .hypertrophy, experience: .intermediate,
                                    now: now, recoveryAwareCoachV2: true)
        // Abs is the only deficit so the single strength slot routes there.
        let facts = trainingFacts([
            .legs: 16, .back: 16, .chest: 16, .shoulders: 16,
            .biceps: 14, .triceps: 14, .calves: 12,
            .abs: 1,
        ])
        let plan = weeklyPlan(now: now, days: [(1, [.strength])])

        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: plan,
            schedulePreferences: preferences(twoADays: true),
            candidates: [genericStrengthSession()])

        let absExercise = optimized.plannedStrengthSessions
            .flatMap { $0.exercises ?? [] }
            .first { $0.name == "Crunch" }
        let ex = try XCTUnwrap(absExercise, "coach should route abs volume to the user's crunches")
        XCTAssertEqual(ex.repsHigh, 40, "prescription tracks the logged 40-rep top set")
        XCTAssertEqual(ex.repsLow, 20, "history-based high-rep range uses a conservative half-top-set floor")
        XCTAssertEqual(Array((ex.repLadder ?? []).prefix(3)), [40, 30, 20],
                       "high-rep bodyweight ladders drop by 10 reps, not 2")
    }

    func testLowRepBodyweightDoesNotUseHighRepDecrement() {
        let pullUpRange = PrescriptionMath.repRange(forExerciseNamed: "Pull-Up", goal: .hypertrophy)
        XCTAssertEqual(pullUpRange, TrainingGoal.hypertrophy.repRange)
        XCTAssertEqual(
            RepLadder.ladder(low: pullUpRange.lowerBound, high: pullUpRange.upperBound, sets: 3),
            [12, 10, 8]
        )

        let muscleUpRange = PrescriptionMath.repRange(forExerciseNamed: "Muscle-Up", goal: .strength,
                                                      recentTopReps: 8)
        XCTAssertLessThan(muscleUpRange.upperBound, 30)
        XCTAssertNotEqual(
            RepLadder.ladder(low: muscleUpRange.lowerBound, high: muscleUpRange.upperBound, sets: 3),
            [8, 3, 3]
        )
    }

    // MARK: - Helpers

    private func preferences(twoADays: Bool) -> CoachSchedulePreferences {
        CoachSchedulePreferences(
            strengthDaysPerWeek: 1,
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
            allTimeWorkingSets: max(1, Int(sets.values.reduce(0, +).rounded(.up))),
            goal: .hypertrophy,
            experience: .intermediate)
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
