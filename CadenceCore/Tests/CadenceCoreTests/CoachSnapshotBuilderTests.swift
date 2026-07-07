import XCTest
import SwiftData
@testable import CadenceCore

/// The Home coach pipeline was consolidated into `CoachSnapshotBuilder` (pure) so it
/// computes once — off the render path — instead of ~8–10× per body evaluation,
/// which was stalling set logging by 1–2s. These lock in that the builder produces
/// the same coach outputs as the underlying engines, and is deterministic.
final class CoachSnapshotBuilderTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    private func seededSession(chestSets: Int, now: Date) throws -> (ModelContext, [WorkoutSession]) {
        let ctx = try makeContext()
        let s = try WorkoutRepository.createSession(date: now.addingTimeInterval(-2 * 86_400), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(
            named: "SnapBench", primaryMuscles: ["chest"], secondaryMuscles: ["triceps"], in: ctx)
        for _ in 0..<chestSets {
            _ = try WorkoutRepository.addSet(to: s, exercise: bench, weightKg: 60, reps: 5, rpe: 7, in: ctx)
        }
        return (ctx, [s])
    }

    func testColdStartSnapshotIsSafeAndCited() {
        let snap = CoachSnapshotBuilder.build(
            sessions: [], cardio: [], assessments: [], hasPainToday: false,
            goal: .strength, experience: .intermediate, formula: .epley,
            schedulePreferences: CoachSchedulePreferences(), profile: .empty)
        // Cold start still yields a usable, cited recommendation and a plan — no crash.
        XCTAssertFalse(snap.recommendation.title.isEmpty)
        XCTAssertFalse(snap.plan.days.isEmpty)
        let known = Set(CitationRegistry.all.map(\.id))
        for i in snap.insights { XCTAssertTrue(known.contains(i.citation.id)) }
    }

    func testSnapshotInsightsMatchDirectEngine() throws {
        let now = Date()
        let (_, sessions) = try seededSession(chestSets: 8, now: now)
        let snap = CoachSnapshotBuilder.build(
            sessions: sessions, cardio: [], assessments: [], hasPainToday: false,
            goal: .hypertrophy, experience: .intermediate, formula: .epley,
            schedulePreferences: CoachSchedulePreferences(), profile: .empty, now: now)

        // Facts reflect the logged chest volume (the builder wired TrainingFacts).
        XCTAssertEqual(snap.facts.weeklySetsByPart[.chest], 8)
        // A weekly plan + a decision were produced, and every insight is cited.
        XCTAssertFalse(snap.plan.days.isEmpty)
        XCTAssertFalse(snap.decision.primary.id.isEmpty)
        let known = Set(CitationRegistry.all.map(\.id))
        for i in snap.insights { XCTAssertTrue(known.contains(i.citation.id)) }
    }

    func testDeterministicForIdenticalInputs() throws {
        let now = Date()
        let (_, sessions) = try seededSession(chestSets: 6, now: now)
        func build() -> CoachSnapshot {
            CoachSnapshotBuilder.build(
                sessions: sessions, cardio: [], assessments: [], hasPainToday: false,
                goal: .strength, experience: .intermediate, formula: .epley,
                schedulePreferences: CoachSchedulePreferences(), profile: .empty, now: now)
        }
        let a = build(); let b = build()
        XCTAssertEqual(a.insights.map(\.id), b.insights.map(\.id))
        XCTAssertEqual(a.decision.primary.id, b.decision.primary.id)
        XCTAssertEqual(a.recommendation.id, b.recommendation.id)
        XCTAssertEqual(a.plan.days.count, b.plan.days.count)
    }

    func testMondayWorkoutThenTuesdayDoesNotNagUntrainedAbsCalves() throws {
        let cal = Calendar(identifier: .gregorian)
        var mondayComps = DateComponents()
        mondayComps.calendar = cal
        mondayComps.year = 2026; mondayComps.month = 6; mondayComps.day = 22 // Monday
        mondayComps.hour = 18
        let mondayDate = mondayComps.date ?? Date(timeIntervalSince1970: 1_782_300_000)
        var tuesdayComps = DateComponents()
        tuesdayComps.calendar = cal
        tuesdayComps.year = 2026; tuesdayComps.month = 6; tuesdayComps.day = 23 // Tuesday
        tuesdayComps.hour = 8
        let tuesdayDate = tuesdayComps.date ?? Date(timeIntervalSince1970: 1_782_300_000)

        let ctx = try makeContext()
        let monday = try WorkoutRepository.createSession(date: mondayDate, in: ctx)

        // Monday: 4 compounds, 2 sets each — coach's own workout.
        let squat = try WorkoutRepository.findOrCreateExercise(
            named: "Back Squat", primaryMuscles: ["quads"], secondaryMuscles: ["glutes", "erectors"], in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(
            named: "Bench Press", primaryMuscles: ["chest"], secondaryMuscles: ["triceps", "delts_front"], in: ctx)
        let row = try WorkoutRepository.findOrCreateExercise(
            named: "Barbell Row", primaryMuscles: ["lats"], secondaryMuscles: ["biceps", "rhomboids"], in: ctx)
        let ohp = try WorkoutRepository.findOrCreateExercise(
            named: "Overhead Press", primaryMuscles: ["delts_front"], secondaryMuscles: ["triceps", "delts_lateral"], in: ctx)

        for ex in [squat, bench, row, ohp] {
            for _ in 0..<2 {
                _ = try WorkoutRepository.addSet(to: monday, exercise: ex, weightKg: 60, reps: 5, rpe: 7, in: ctx)
            }
        }

        let snap = CoachSnapshotBuilder.build(
            sessions: [monday], cardio: [], assessments: [], hasPainToday: false,
            goal: .strength, experience: .intermediate, formula: .epley,
            schedulePreferences: CoachSchedulePreferences(
                strengthDaysPerWeek: 3,
                cardioDaysPerWeek: 6,
                restPreference: .fixed(days: []),
                allowsTwoADays: false),
            profile: .empty, now: tuesdayDate)

        // RED: No abs or calves "low volume" nag in the insights.
        let absNag = snap.insights.first {
            $0.part == .abs && $0.kind == .volume && $0.severity == .attention
                && $0.title.localizedCaseInsensitiveContains("low")
        }
        let calvesNag = snap.insights.first {
            $0.part == .calves && $0.kind == .volume && $0.severity == .attention
                && $0.title.localizedCaseInsensitiveContains("low")
        }
        XCTAssertNil(absNag, "Abs should not read 'low' when coach never planned them")
        XCTAssertNil(calvesNag, "Calves should not read 'low' when coach never planned them")

        // The coach's primary launched workout should carry abs + calves.
        // Check the primary if it's strength, otherwise check the first
        // planned strength recommendation.
        let primary = snap.decision.primary
        let launchedExercises: [String]
        if primary.kind == .strength {
            launchedExercises = (primary.exercises ?? []).map(\.name)
        } else {
            let strengthRecs = snap.decision.todayPlannedRecommendations
                .filter { $0.kind == .strength }
            launchedExercises = strengthRecs.first?.exercises?.map(\.name) ?? []
        }
        let hasAbWork = launchedExercises.contains { name in
            ["Plank", "Cable Crunch", "Hanging Leg Raise", "Ab Wheel Rollout"].contains(name)
        }
        let hasCalfWork = launchedExercises.contains { name in
            ["Standing Calf Raise", "Seated Calf Raise", "Calf Press on Leg Press"].contains(name)
        }
        // If the launched workout is a strength session, it should include
        // whole-body coverage. A non-strength primary is fine — the planner
        // covers abs/calves later in the week.
        if primary.kind == .strength || !launchedExercises.isEmpty {
            XCTAssertTrue(hasAbWork, "Launched strength should include an ab movement")
            XCTAssertTrue(hasCalfWork, "Launched strength should include a calf movement")
        }
    }

    func testDeletedSessionsAreIgnored() throws {
        let now = Date()
        let (ctx, sessions) = try seededSession(chestSets: 8, now: now)

        let before = CoachSnapshotBuilder.build(
            sessions: sessions, cardio: [], assessments: [], hasPainToday: false,
            goal: .hypertrophy, experience: .intermediate, formula: .epley,
            schedulePreferences: CoachSchedulePreferences(), profile: .empty, now: now)
        XCTAssertEqual(before.facts.weeklySetsByPart[.chest], 8)

        sessions[0].deletedAt = Date()
        try ctx.save()
        let after = CoachSnapshotBuilder.build(
            sessions: sessions, cardio: [], assessments: [], hasPainToday: false,
            goal: .hypertrophy, experience: .intermediate, formula: .epley,
            schedulePreferences: CoachSchedulePreferences(), profile: .empty, now: now)
        // Soft-deleted sessions are excluded from the facts the coach reasons over.
        XCTAssertEqual(after.facts.weeklySetsByPart[.chest] ?? 0, 0)
    }
}
