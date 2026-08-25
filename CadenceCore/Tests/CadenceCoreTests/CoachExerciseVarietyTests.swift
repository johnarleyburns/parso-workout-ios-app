import XCTest
import SwiftData
@testable import CadenceCore

/// Regression coverage for the "rotary torso every day" defect: a movement
/// pattern's *exercise identity* must rotate across the days of a generated plan
/// instead of pinning the single most-trained favorite to every session.
final class CoachExerciseVarietyTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private func fixedWednesday() -> Date {
        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.year = 2026; comps.month = 6; comps.day = 24; comps.hour = 12
        return comps.date ?? Date(timeIntervalSince1970: 1_782_300_000)
    }

    // MARK: - Ranked candidate list

    func testTrainedExerciseCandidatesRanksMostTrainedFirst() throws {
        let ctx = try makeContext()
        let now = fixedWednesday()
        let events = try coreHistory(context: ctx, now: now)
        let facts = CoachFacts.make(from: events, goal: .hypertrophy, experience: .intermediate,
                                    now: now, recoveryAwareCoachV2: true)

        let all = CoachSession.trainedExerciseCandidates(facts: facts)
        let ranked = all[.core] ?? []
        let everyTrainedName = all.values.flatMap { $0 }
        XCTAssertEqual(ranked.first, "Rotary Torso",
                       "Most-trained core movement ranks first in its pattern")
        XCTAssertTrue(everyTrainedName.contains("Rotary Torso"),
                      "The dominant lift appears in the ranked candidates")
        XCTAssertTrue(everyTrainedName.contains("Cable Crunch"),
                      "Less-trained lifts still appear in the ranked candidates")
        XCTAssertEqual(CoachSession.mostTrainedExercises(facts: facts)[.core], ranked.first,
                       "mostTrainedExercises is the first of the ranked candidate list")
    }

    // MARK: - Cross-day rotation

    func testCoreExerciseRotatesAcrossPlannedDays() throws {
        let ctx = try makeContext()
        let now = fixedWednesday()
        let events = try coreHistory(context: ctx, now: now)
        let coach = CoachFacts.make(from: events, goal: .hypertrophy, experience: .intermediate,
                                    now: now, recoveryAwareCoachV2: true)

        // Abdominals are the only tracked group below their starting range;
        // everything else is already well covered, so both planned strength days
        // route to abs. Every tracked group has to be named — DB++ tracks 13, and an
        // unnamed group would read as a zero-volume deficit and out-rank abs.
        var sets = Dictionary(uniqueKeysWithValues: MuscleGroup.defaultTracked.map { ($0, 16.0) })
        sets[.abdominals] = 1
        let facts = trainingFacts(sets)
        let plan = weeklyPlan(now: now, days: [(1, [.strength]), (3, [.strength])])

        let optimized = CoachPlanOptimizer.optimize(
            trainingFacts: facts,
            coachFacts: coach,
            weeklyPlan: plan,
            schedulePreferences: preferences(twoADays: true),
            candidates: [genericStrengthSession()])

        XCTAssertEqual(optimized.plannedStrengthSessions.count, 2,
                       "Both strength slots should be planned")

        let perSessionCoreNames = optimized.plannedStrengthSessions.map { session in
            Set((session.exercises ?? [])
                .filter { CoachPlanOptimizer_partsCoveredIsAbs($0) }
                .map(\.name))
        }
        let allCoreNames = perSessionCoreNames.reduce(into: Set<String>()) { $0.formUnion($1) }

        XCTAssertTrue(perSessionCoreNames.allSatisfy { !$0.isEmpty },
                      "Every planned strength day should include the abs work it was routed for")
        XCTAssertGreaterThanOrEqual(allCoreNames.count, 2,
            "The core exercise identity must rotate across days, not repeat one favorite: \(allCoreNames)")
    }

    // MARK: - Helpers

    /// True when a recommended exercise trains the abdominals.
    private func CoachPlanOptimizer_partsCoveredIsAbs(_ ex: CoachSession.RecommendedExercise) -> Bool {
        let ids = ex.primaryMuscles.isEmpty
            ? (ExerciseLibrary.byName[ex.name.lowercased()]?.primaryMuscles
               ?? ExerciseCategory.guess(fromName: ex.name)
                    .map { MuscleGroup.defaults(forCategory: $0).map(\.rawValue) } ?? [])
            : ex.primaryMuscles
        return MuscleGroup.canonicalize(ids).contains(.abdominals)
    }

    private func coreHistory(context: ModelContext, now: Date) throws -> [TrainingEvent] {
        // Rotary Torso dominates (2 sessions × 4 sets); Cable Crunch is a real but
        // less-trained alternative. Dated well outside any recovery window so both
        // stay eligible and carry no soft-recency penalty.
        var events: [TrainingEvent] = []
        for daysAgo in [11, 9] {
            let date = now.addingTimeInterval(Double(-daysAgo) * 86400)
            let session = try WorkoutRepository.createSession(date: date, in: context)
            let rotary = try WorkoutRepository.findOrCreateExercise(
                named: "Rotary Torso", primaryMuscles: ["obliques"], secondaryMuscles: ["abs"], in: context)
            for _ in 0..<4 {
                _ = try WorkoutRepository.addSet(to: session, exercise: rotary, weightKg: 30, reps: 20,
                                                 completedAt: date, in: context)
            }
            session.endedAt = date.addingTimeInterval(1800)
            try context.save()
            events.append(TrainingEvent.from(session: session)!)
        }
        let crunchDate = now.addingTimeInterval(-10 * 86400)
        let crunchSession = try WorkoutRepository.createSession(date: crunchDate, in: context)
        let crunch = try WorkoutRepository.findOrCreateExercise(
            named: "Cable Crunch", primaryMuscles: ["abs"], in: context)
        for _ in 0..<3 {
            _ = try WorkoutRepository.addSet(to: crunchSession, exercise: crunch, weightKg: 40, reps: 15,
                                             completedAt: crunchDate, in: context)
        }
        crunchSession.endedAt = crunchDate.addingTimeInterval(1800)
        try context.save()
        events.append(TrainingEvent.from(session: crunchSession)!)
        return events
    }

    private func preferences(twoADays: Bool) -> CoachSchedulePreferences {
        CoachSchedulePreferences(
            strengthDaysPerWeek: 2,
            cardioDaysPerWeek: 3,
            restPreference: .fixed(days: []),
            allowsTwoADays: twoADays)
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
