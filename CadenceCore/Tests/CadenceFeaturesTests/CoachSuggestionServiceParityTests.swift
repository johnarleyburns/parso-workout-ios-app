import XCTest
@testable import CadenceCore
import CadenceFeatures

final class CoachSuggestionServiceParityTests: XCTestCase {
    private typealias F = CoachSuggestionFixtures

    private func assertParity(_ request: CoachSuggestionRequest,
                              file: StaticString = #filePath, line: UInt = #line) throws
        -> SuggestedWorkoutOption {
        let snapshot = F.snapshot(request)
        // Watch receives the snapshot over a value transport.
        let wire = try PropertyListEncoder().encode(snapshot)
        guard case .success(let watchSnapshot) = CoachSuggestionSnapshot.decode(wire) else {
            XCTFail("decode", file: file, line: line); throw CancellationError()
        }
        let phone = try XCTUnwrap(CoachSuggestionService.generate(from: snapshot), file: file, line: line)
        let watch = try XCTUnwrap(CoachSuggestionService.generate(from: watchSnapshot), file: file, line: line)
        XCTAssertEqual(phone, watch, file: file, line: line)
        let direct = SuggestedWorkoutGenerator.generatePersonalized(input: request.input)
        XCTAssertEqual(phone, direct, file: file, line: line)

        func plan(_ o: SuggestedWorkoutOption) -> EditablePlan {
            SuggestedWorkoutPresenter.editablePlan(for: o, unit: request.unit,
                warmupMinutes: request.warmupMinutes, cooldownMinutes: request.cooldownMinutes)
        }
        let p = plan(phone), w = plan(watch)
        XCTAssertEqual(project(p), project(w), file: file, line: line)
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

    func testPersonalizedHistoryFixture() throws {
        let option = try assertParity(F.request(candidates: F.catalog))
        XCTAssertFalse(option.exercises.isEmpty)
    }

    func testRecentExclusionRemovesRecentCandidates() throws {
        let option = try assertParity(F.request(candidates: F.catalog, recent: ["bench", "row"]))
        let ids = Set(option.exercises.map(\.candidateID))
        XCTAssertFalse(ids.contains("bench"))
        XCTAssertFalse(ids.contains("row"))
    }

    func testCustomLimitedCatalog() throws {
        let option = try assertParity(F.request(
            candidates: [F.candidate("custom-press", "Custom Press", "chest", personalized: true),
                         F.candidate("custom-row", "Custom Row", "lats")],
            tracked: [.chest, .lats]))
        XCTAssertTrue(Set(option.exercises.map(\.candidateID)).isSubset(of: ["custom-press", "custom-row"]))
    }

    func testYesterdaysWorkoutIsNotRepeatedOnBothHosts() throws {
        // Yesterday's strength workout used bench + row; older history exists.
        let option = try assertParity(F.request(candidates: F.catalog, recent: ["bench", "row"]))
        XCTAssertTrue(option.exercises.contains { !["bench", "row"].contains($0.candidateID) })
        XCTAssertTrue(option.exercises.allSatisfy { !["bench", "row"].contains($0.candidateID) })
    }

    func testResultIsIndependentOfWallClock() {
        let snapshot = F.snapshot(F.request(candidates: F.catalog, recent: ["bench"]))
        let first = CoachSuggestionService.generate(from: snapshot)
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(first, CoachSuggestionService.generate(from: snapshot))
    }

    func testFailureMessageProducesNoSuggestion() {
        var r = F.request(candidates: F.catalog)
        r = CoachSuggestionRequest(input: r.input, unit: r.unit, warmupMinutes: 5,
                                   cooldownMinutes: 5, failureMessage: "x")
        XCTAssertNil(CoachSuggestionService.generate(from: F.snapshot(r)))
    }
}
