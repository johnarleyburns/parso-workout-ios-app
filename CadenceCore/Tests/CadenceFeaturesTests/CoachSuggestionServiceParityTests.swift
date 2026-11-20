import Foundation
import Testing
@testable import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

struct CoachSuggestionServiceParityTests {
    private typealias F = CoachSuggestionFixtures

    private func assertParity(_ request: CoachSuggestionRequest,
                              sourceLocation: SourceLocation = #_sourceLocation) throws
        -> SuggestedWorkoutOption {
        let snapshot = F.snapshot(request)
        // Watch receives the snapshot over a value transport.
        let wire = try PropertyListEncoder().encode(snapshot)
        guard case .success(let watchSnapshot) = CoachSuggestionSnapshot.decode(wire) else {
            Issue.record("decode", sourceLocation: sourceLocation); throw CancellationError()
        }
        let phone = try #require(CoachSuggestionService.generate(from: snapshot), sourceLocation: sourceLocation)
        let watch = try #require(CoachSuggestionService.generate(from: watchSnapshot), sourceLocation: sourceLocation)
        #expect(phone == watch, sourceLocation: sourceLocation)
        let direct = SuggestedWorkoutGenerator.generatePersonalized(input: request.input)
        #expect(phone == direct, sourceLocation: sourceLocation)

        func plan(_ o: SuggestedWorkoutOption) -> EditablePlan {
            SuggestedWorkoutPresenter.editablePlan(for: o, unit: request.unit,
                warmupMinutes: request.warmupMinutes, cooldownMinutes: request.cooldownMinutes)
        }
        let p = plan(phone), w = plan(watch)
        #expect(project(p) == project(w), sourceLocation: sourceLocation)
        return phone
    }

    /// Prescription projection without the per-materialization random UUIDs.
    private func project(_ p: EditablePlan) -> String {
        let exercises = p.exercises.map { e in
            let sets = e.sets.map {
                "\($0.targetReps)|\(String(describing: $0.targetWeight))|\($0.loadMode)|\(String(describing: $0.oneRepMaxPercent))"
            }
            return "\(e.name)|\(String(describing: e.supersetGroup))|\(sets)"
        }
        return "\(p.title)|\(p.warmupMinutes)|\(p.cooldownMinutes)|\(exercises)|\(String(describing: p.recommendationRationale))"
    }

    @Test func personalizedHistoryFixture() throws {
        let option = try assertParity(F.request(candidates: F.catalog))
        #expect(!option.exercises.isEmpty)
    }

    @Test func recentExclusionRemovesRecentCandidates() throws {
        let option = try assertParity(F.request(candidates: F.catalog, recent: ["bench", "row"]))
        let ids = Set(option.exercises.map(\.candidateID))
        #expect(!ids.contains("bench"))
        #expect(!ids.contains("row"))
    }

    @Test func customLimitedCatalog() throws {
        let option = try assertParity(F.request(
            candidates: [F.candidate("custom-press", "Custom Press", "chest", personalized: true),
                         F.candidate("custom-row", "Custom Row", "lats")],
            tracked: [.chest, .lats]))
        #expect(Set(option.exercises.map(\.candidateID)).isSubset(of: ["custom-press", "custom-row"]))
    }

    @Test func yesterdaysWorkoutIsNotRepeatedOnBothHosts() throws {
        // Yesterday's strength workout used bench + row; older history exists.
        let option = try assertParity(F.request(candidates: F.catalog, recent: ["bench", "row"]))
        #expect(option.exercises.contains { !["bench", "row"].contains($0.candidateID) })
        #expect(option.exercises.allSatisfy { !["bench", "row"].contains($0.candidateID) })
    }

    @Test func resultIsIndependentOfWallClock() async {
        let snapshot = F.snapshot(F.request(candidates: F.catalog, recent: ["bench"]))
        let first = CoachSuggestionService.generate(from: snapshot)
        try? await Task.sleep(for: .seconds(0.05))
        #expect(first == CoachSuggestionService.generate(from: snapshot))
    }

    @Test func failureMessageProducesNoSuggestion() {
        var r = F.request(candidates: F.catalog)
        r = CoachSuggestionRequest(input: r.input, unit: r.unit, warmupMinutes: 5,
                                   cooldownMinutes: 5, failureMessage: "x")
        #expect(CoachSuggestionService.generate(from: F.snapshot(r)) == nil)
    }
}
