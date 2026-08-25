import XCTest
@testable import CadenceCore

final class ExerciseSimilarityTests: XCTestCase {
    private func movement(_ name: String, direct: Set<MuscleGroup>, indirect: Set<MuscleGroup>, type: ExerciseTrainingType = .strength, id: String? = nil) -> ExerciseSimilarity.Prepared {
        ExerciseSimilarity.Prepared(id: id ?? name, name: name, direct: direct, indirect: indirect, trainingTypes: [type])
    }

    func testIdenticalMappingScoresOne() {
        let source = movement("Bench", direct: [.chest], indirect: [.triceps, .shoulders])
        let result = try! XCTUnwrap(ExerciseSimilarity.score(source: source, candidate: movement("Press", direct: [.chest], indirect: [.triceps, .shoulders])))
        XCTAssertEqual(result.score, 0.65, accuracy: 0.0001)
        XCTAssertEqual(result.directOverlap, 1)
        XCTAssertEqual(result.indirectOverlap, 1)
    }

    func testDirectOverlapOutranksIndirectOnly() {
        let source = movement("Bench", direct: [.chest], indirect: [.triceps])
        let direct = movement("Press", direct: [.chest], indirect: [])
        let indirect = movement("Extension", direct: [.shoulders], indirect: [.triceps])
        XCTAssertEqual(ExerciseSimilarity.rank(source: source, candidates: [indirect, direct]).first?.candidate.name, "Press")
    }

    func testTypeBiasStillReturnsBorrowedResults() {
        let source = movement("Curl", direct: [.biceps], indirect: [], type: .strength)
        let strongman = movement("Carry", direct: [.biceps], indirect: [], type: .strongman)
        let results = ExerciseSimilarity.rank(source: source, candidates: [strongman], selectedType: .strength)
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].borrowed)
    }

    func testSourceIsExcludedAndResultsAreDescending() {
        let source = movement("Bench", direct: [.chest], indirect: [])
        let one = movement("Press", direct: [.chest], indirect: [])
        let two = movement("Row", direct: [.lats], indirect: [])
        let results = ExerciseSimilarity.rank(source: source, candidates: [two, source, one])
        XCTAssertEqual(results.map { $0.candidate.name }, ["Press", "Row"])
    }
}
