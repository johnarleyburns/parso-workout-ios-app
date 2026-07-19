import XCTest
import SwiftData
import CadenceCore
@testable import CadenceFeatures

/// Phase G (field-test-fixes): per-rep-count weight autofill + inverse-e1RM.
final class WeightSuggestionTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    // MARK: - exactRepMatchWins

    func testExactRepMatchWins() {
        let history: [SetSample] = [
            SetSample(weight: 80, reps: 5, date: Date().addingTimeInterval(-3600)),
            SetSample(weight: 60, reps: 8, date: Date().addingTimeInterval(-7200)),
        ]
        let result = WeightSuggestion.suggest(targetReps: 8, history: history)
        XCTAssertNotNil(result)
        if let r = result { XCTAssertEqual(r.weightKg, 60, accuracy: 0.01) }
        XCTAssertEqual(result?.basis, .exactRepMatch)
    }

    // MARK: - mostRecentExactMatchPreferred

    func testMostRecentExactMatchPreferred() {
        let history: [SetSample] = [
            SetSample(weight: 90, reps: 5, date: Date().addingTimeInterval(-1800)),
            SetSample(weight: 75, reps: 5, date: Date().addingTimeInterval(-7200)),
        ]
        let result = WeightSuggestion.suggest(targetReps: 5, history: history)
        if let r = result { XCTAssertEqual(r.weightKg, 90, accuracy: 0.01, "Should pick most recent") } else { XCTFail() }
    }

    // MARK: - e1RMScalesFromBestRecentSet

    func testE1RMScalesFromBestRecentSet() {
        // Only 5-rep sets in history but target is 8. Best 5-rep set: 80kg.
        // Epley e1RM = 80 * (1 + 5/30) = 80 * 1.1667 = 93.33
        // Inverse for 8 reps: 93.33 / (1 + 8/30) = 93.33 / 1.2667 = 73.68
        let history: [SetSample] = [
            SetSample(weight: 80, reps: 5, date: Date().addingTimeInterval(-1800)),
            SetSample(weight: 75, reps: 5, date: Date().addingTimeInterval(-7200)),
        ]
        let result = WeightSuggestion.suggest(targetReps: 8, history: history)
        guard let r = result else { return XCTFail() }
        XCTAssertEqual(r.basis, .estimatedFromE1RM)
        XCTAssertEqual(r.weightKg, 73.68, accuracy: 0.1)
        XCTAssertFalse(r.citationIds.isEmpty, "e1RM suggestion must cite science")
    }

    // MARK: - e1RMUsesChosenFormula

    func testE1RMUsesChosenFormula() {
        let history: [SetSample] = [
            SetSample(weight: 100, reps: 5, date: Date()),
        ]
        let epley = WeightSuggestion.suggest(targetReps: 10, history: history, formula: .epley)
        let brzycki = WeightSuggestion.suggest(targetReps: 10, history: history, formula: .brzycki)

        XCTAssertNotNil(epley)
        XCTAssertNotNil(brzycki)
        // Different formulas produce different weight estimates.
        XCTAssertNotEqual(epley?.weightKg, brzycki?.weightKg, "Epley and Brzycki should differ")
    }

    // MARK: - warmupsExcluded

    func testWarmupsExcluded() {
        let history: [SetSample] = [
            SetSample(weight: 100, reps: 5, date: Date(), isWarmup: true),
            SetSample(weight: 20, reps: 8, date: Date().addingTimeInterval(-3600)),
        ]
        let result = WeightSuggestion.suggest(targetReps: 8, history: history)
        XCTAssertEqual(result?.weightKg, 20, "Should use the non-warmup 20kg set")
    }

    // MARK: - partnerHistoryFullySeparated

    func testPartnerHistoryFullySeparated() throws {
        let ctx = try makeContext()
        let now = Date()
        let session = try WorkoutRepository.createSession(in: ctx)
        let ex = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", primaryMuscles: ["chest"], in: ctx)
        let owner = try WorkoutRepository.me(in: ctx)
        let partner = Person(name: "Partner")
        ctx.insert(partner)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 80, reps: 5, rpe: 8,
                                          performedBy: owner, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 40, reps: 5, rpe: 6,
                                          performedBy: partner, in: ctx)
        session.endedAt = now
        try ctx.save()

        let ownerHistory = WorkoutRepository.performerSetHistory(for: ex, performedBy: owner, excluding: nil)
        let partnerHistory = WorkoutRepository.performerSetHistory(for: ex, performedBy: partner, excluding: nil)

        // Owner's history should include 80kg, not partner's 40kg
        XCTAssertTrue(ownerHistory.contains(where: { $0.weight == 80 }))
        XCTAssertFalse(ownerHistory.contains(where: { $0.weight == 40 }))
        XCTAssertFalse(partnerHistory.contains(where: { $0.weight == 80 }))
        XCTAssertTrue(partnerHistory.contains(where: { $0.weight == 40 }))
    }

    // MARK: - roundTripSelfConsistency

    func testRoundTripSelfConsistency() {
        // If we have a 5-rep set at 80kg and ask for 5 reps, we get 80kg.
        let history: [SetSample] = [SetSample(weight: 80, reps: 5, date: Date())]
        let result = WeightSuggestion.suggest(targetReps: 5, history: history)
        XCTAssertEqual(result?.weightKg, 80, "Exact match should return the same weight")
        XCTAssertEqual(result?.basis, .exactRepMatch)
    }

    // MARK: - noHistoryReturnsNil

    func testNoHistoryReturnsNil() {
        let result = WeightSuggestion.suggest(targetReps: 8, history: [])
        XCTAssertNil(result, "Empty history should return nil")
    }

    // MARK: - everyEmittedCitationIdResolves

    func testEveryEmittedCitationIdResolves() {
        let history: [SetSample] = [
            SetSample(weight: 80, reps: 5, date: Date()),
        ]
        let result = WeightSuggestion.suggest(targetReps: 10, history: history)
        guard let result else { return }
        for id in result.citationIds {
            XCTAssertNotNil(CitationRegistry.citation(forId: id),
                            "Citation ID '\(id)' must resolve in CitationRegistry")
        }
    }
}
