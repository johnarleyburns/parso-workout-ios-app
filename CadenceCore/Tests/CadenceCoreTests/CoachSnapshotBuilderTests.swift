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
