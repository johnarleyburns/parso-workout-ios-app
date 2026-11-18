#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

/// Phase G (field-test-fixes): per-rep-count weight autofill + inverse-e1RM.
struct WeightSuggestionTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    // MARK: - exactRepMatchWins

    @Test func exactRepMatchWins() {
        let history: [SetSample] = [
            SetSample(weight: 80, reps: 5, date: Date().addingTimeInterval(-3600)),
            SetSample(weight: 60, reps: 8, date: Date().addingTimeInterval(-7200)),
        ]
        let result = WeightSuggestion.suggest(targetReps: 8, history: history)
        #expect(result != nil)
        if let r = result { #expect(abs(r.weightKg - 60) <= 0.01) }
        #expect(result?.basis == .exactRepMatch)
    }

    // MARK: - mostRecentExactMatchPreferred

    @Test func mostRecentExactMatchPreferred() {
        let history: [SetSample] = [
            SetSample(weight: 90, reps: 5, date: Date().addingTimeInterval(-1800)),
            SetSample(weight: 75, reps: 5, date: Date().addingTimeInterval(-7200)),
        ]
        let result = WeightSuggestion.suggest(targetReps: 5, history: history)
        if let r = result { #expect(abs(r.weightKg - 90) <= 0.01, "Should pick most recent") } else { Issue.record() }
    }

    @Test func mostRecentExactMatchPreferredEvenWhenInputUnsorted() {
        // The exact-rep match must be resolved by `date`, not array order, so
        // an older set cannot win merely because it appears first (field
        // report: invalid set default).
        let history: [SetSample] = [
            SetSample(weight: 75, reps: 5, date: Date().addingTimeInterval(-7200)),
            SetSample(weight: 90, reps: 5, date: Date().addingTimeInterval(-1800)),
        ]
        let result = WeightSuggestion.suggest(targetReps: 5, history: history)
        if let r = result {
            #expect(abs(r.weightKg - 90) <= 0.01, "Should pick most recent by date")
        } else {
            Issue.record()
        }
    }

    // MARK: - e1RMScalesFromBestRecentSet

    @Test func e1RMScalesFromBestRecentSet() throws {
        // Only 5-rep sets in history but target is 8. Best 5-rep set: 80kg.
        // Epley e1RM = 80 * (1 + 5/30) = 80 * 1.1667 = 93.33
        // Inverse for 8 reps: 93.33 / (1 + 8/30) = 93.33 / 1.2667 = 73.68
        let history: [SetSample] = [
            SetSample(weight: 80, reps: 5, date: Date().addingTimeInterval(-1800)),
            SetSample(weight: 75, reps: 5, date: Date().addingTimeInterval(-7200)),
        ]
        let result = WeightSuggestion.suggest(targetReps: 8, history: history)
        let r = try #require(result)
        #expect(r.basis == .estimatedFromE1RM)
        #expect(abs(r.weightKg - 73.68) <= 0.1)
        #expect(!r.citationIds.isEmpty, "e1RM suggestion must cite science")
    }

    // MARK: - e1RMUsesChosenFormula

    @Test func e1RMUsesChosenFormula() {
        let history: [SetSample] = [
            SetSample(weight: 100, reps: 5, date: Date()),
        ]
        let epley = WeightSuggestion.suggest(targetReps: 10, history: history, formula: .epley)
        let brzycki = WeightSuggestion.suggest(targetReps: 10, history: history, formula: .brzycki)

        #expect(epley != nil)
        #expect(brzycki != nil)
        // Different formulas produce different weight estimates.
        #expect(epley?.weightKg != brzycki?.weightKg, "Epley and Brzycki should differ")
    }

    // MARK: - warmupsExcluded

    @Test func warmupsExcluded() {
        let history: [SetSample] = [
            SetSample(weight: 100, reps: 5, date: Date(), isWarmup: true),
            SetSample(weight: 20, reps: 8, date: Date().addingTimeInterval(-3600)),
        ]
        let result = WeightSuggestion.suggest(targetReps: 8, history: history)
        #expect(result?.weightKg == 20, "Should use the non-warmup 20kg set")
    }

    // MARK: - partnerHistoryFullySeparated

    @Test func partnerHistoryFullySeparated() throws {
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
        #expect(ownerHistory.contains(where: { $0.weight == 80 }))
        #expect(!ownerHistory.contains(where: { $0.weight == 40 }))
        #expect(!partnerHistory.contains(where: { $0.weight == 80 }))
        #expect(partnerHistory.contains(where: { $0.weight == 40 }))
    }

    // MARK: - roundTripSelfConsistency

    @Test func roundTripSelfConsistency() {
        // If we have a 5-rep set at 80kg and ask for 5 reps, we get 80kg.
        let history: [SetSample] = [SetSample(weight: 80, reps: 5, date: Date())]
        let result = WeightSuggestion.suggest(targetReps: 5, history: history)
        #expect(result?.weightKg == 80, "Exact match should return the same weight")
        #expect(result?.basis == .exactRepMatch)
    }

    // MARK: - noHistoryReturnsNil

    @Test func noHistoryReturnsNil() {
        let result = WeightSuggestion.suggest(targetReps: 8, history: [])
        #expect(result == nil, "Empty history should return nil")
    }

    // MARK: - everyEmittedCitationIdResolves

    @Test func everyEmittedCitationIdResolves() {
        let history: [SetSample] = [
            SetSample(weight: 80, reps: 5, date: Date()),
        ]
        let result = WeightSuggestion.suggest(targetReps: 10, history: history)
        guard let result else { return }
        for id in result.citationIds {
            #expect(CitationRegistry.citation(forId: id) != nil,
                            "Citation ID '\(id)' must resolve in CitationRegistry")
        }
    }
}
#endif
