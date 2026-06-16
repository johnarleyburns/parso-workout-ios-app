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
    private func populatedFacts(chestSets: Int, goal: TrainingGoal) throws -> TrainingFacts {
        let ctx = try makeContext()
        let now = Date()
        let s = try WorkoutRepository.createSession(date: now.addingTimeInterval(-86_400), in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(
            named: "EngineBench", primaryMuscles: ["chest"], secondaryMuscles: ["triceps"], in: ctx)
        for _ in 0..<chestSets {
            _ = try WorkoutRepository.addSet(to: s, exercise: bench, weightKg: 40, reps: 10, rpe: 6, in: ctx)
        }
        return TrainingFacts.make(sessions: [s], now: now, goal: goal, experience: .intermediate)
    }
}
