import XCTest
import SwiftData
@testable import CadenceCore

/// strength-pivot P3 — the read-only inference engine over `TrainingFacts`.
final class InsightEngineTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    // MARK: cold-start

    func testColdStartNeverEmpty() {
        let facts = TrainingFacts.make(sessions: [], goal: .hypertrophy, experience: .intermediate)
        let insights = InsightEngine.run(facts)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights.first?.kind, .coldStart)
        XCTAssertNotNil(InsightEngine.top(facts))
    }

    // MARK: D3 — every insight is cited

    func testEveryInsightCarriesAKnownCitation() throws {
        let knownIDs = Set(CitationRegistry.all.map(\.id))
        let facts = try populatedFacts(chestSets: 4, goal: .strength)  // triggers several rules
        for insight in InsightEngine.run(facts) {
            XCTAssertTrue(knownIDs.contains(insight.citation.id),
                          "\(insight.id) cites unknown \(insight.citation.id)")
        }
    }

    // MARK: volume rule

    func testBelowMEVProducesAttentionInsight() throws {
        let facts = try populatedFacts(chestSets: 4, goal: .hypertrophy)
        let chest = InsightEngine.run(facts).first { $0.id == "volume.chest" }
        XCTAssertEqual(chest?.severity, .attention)
        XCTAssertEqual(chest?.kind, .volume)
    }

    func testProductiveVolumeIsInfoNotAttention() throws {
        let facts = try populatedFacts(chestSets: 12, goal: .hypertrophy)
        let chest = InsightEngine.run(facts).first { $0.id == "volume.chest" }
        XCTAssertEqual(chest?.severity, .info)
    }

    func testPlanAwareInsightsSuppressLowVolumeWhenProjectedPlanMeetsTarget() throws {
        let now = fixedThursday()
        let facts = try populatedFacts(chestSets: 4, goal: .hypertrophy, now: now)
        XCTAssertEqual(InsightEngine.run(facts).first { $0.id == "volume.chest" }?.severity, .attention)

        let insights = PlanAwareInsightEngine.run(
            completed: facts,
            plan: WeeklyPlan(days: [], generatedAt: now),
            plannedStrengthSessions: [plannedBenchSession(sets: 4)],
            now: now)

        XCTAssertNil(insights.first { $0.id == "volume.chest" })
        XCTAssertNil(insights.first { $0.id == "behindPlan.chest" })
    }

    func testPlanAwareInsightsEmitBehindPlanOnlyWhenAdherenceBehind() throws {
        let now = fixedThursday()
        let facts = try populatedFacts(chestSets: 4, goal: .hypertrophy, now: now)
        let plan = WeeklyPlan(days: [], generatedAt: now)
        let planned = [plannedBenchSession(sets: 4)]

        let onPlan = PlanAwareInsightEngine.run(
            completed: facts, plan: plan,
            plannedStrengthSessions: planned,
            isBehindPlan: false,
            now: now)
        XCTAssertNil(onPlan.first { $0.id == "behindPlan.chest" })

        let behind = PlanAwareInsightEngine.run(
            completed: facts, plan: plan,
            plannedStrengthSessions: planned,
            isBehindPlan: true,
            now: now)
        let chest = behind.first { $0.id == "behindPlan.chest" }
        XCTAssertEqual(chest?.severity, .attention)
        XCTAssertTrue(chest?.message.contains("completed so far") ?? false)
        XCTAssertTrue(chest?.message.contains("planned this week") ?? false)
    }

    // MARK: ranking

    func testAttentionRanksBeforeInfo() throws {
        // chest below MEV (attention) should outrank any info insights.
        let facts = try populatedFacts(chestSets: 4, goal: .hypertrophy)
        let insights = InsightEngine.run(facts)
        XCTAssertEqual(insights.first?.severity, .attention)
    }

    // MARK: determinism

    func testIdempotentForIdenticalFacts() throws {
        let facts = try populatedFacts(chestSets: 4, goal: .strength)
        let a = InsightEngine.run(facts).map(\.id)
        let b = InsightEngine.run(facts).map(\.id)
        XCTAssertEqual(a, b)
    }

    // MARK: helpers

    /// A facts snapshot with `chestSets` working sets of bench this week (chest
    /// primary), all light (40 kg) so the strength intensity rule can fire.
    private func populatedFacts(chestSets: Int, goal: TrainingGoal, now fixedNow: Date? = nil) throws -> TrainingFacts {
        let ctx = try makeContext()
        let cal = Calendar.current
        let now: Date
        if let fixedNow {
            now = fixedNow
        } else {
            var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
            comps.weekday = 5; comps.hour = 12; comps.minute = 0; comps.second = 0
            now = cal.date(from: comps) ?? Date()
        }
        let s = try WorkoutRepository.createSession(date: now.addingTimeInterval(-2 * 86_400), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(
            named: "EngineBench", primaryMuscles: ["chest"], secondaryMuscles: ["triceps"], in: ctx)
        for _ in 0..<chestSets {
            _ = try WorkoutRepository.addSet(to: s, exercise: bench, weightKg: 40, reps: 10, rpe: 6, in: ctx)
        }
        return TrainingFacts.make(sessions: [s], now: now, goal: goal, experience: .intermediate)
    }

    private func fixedThursday() -> Date {
        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.year = 2026
        comps.month = 6
        comps.day = 25
        comps.hour = 12
        return comps.date ?? Date(timeIntervalSince1970: 1_782_388_800)
    }

    private func plannedBenchSession(sets: Int) -> CoachSession {
        CoachSession(
            id: "test.strength",
            kind: .strength,
            title: "Strength",
            exercises: [
                CoachSession.RecommendedExercise(name: "Bench Press", sets: sets)
            ],
            launchPayload: .strengthPlan("test"))
    }
}
