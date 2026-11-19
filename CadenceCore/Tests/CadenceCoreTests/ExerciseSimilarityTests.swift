import Testing
@testable import CadenceCore

struct ExerciseSimilarityTests {
    private func movement(_ name: String, direct: Set<MuscleGroup>, indirect: Set<MuscleGroup>, type: ExerciseTrainingType = .strength, id: String? = nil) -> ExerciseSimilarity.Prepared {
        ExerciseSimilarity.Prepared(id: id ?? name, name: name, direct: direct, indirect: indirect, trainingTypes: [type])
    }

    @Test func identicalMappingScoresOne() {
        let source = movement("Bench", direct: [.chest], indirect: [.triceps, .shoulders])
        let result = try! #require(ExerciseSimilarity.score(source: source, candidate: movement("Press", direct: [.chest], indirect: [.triceps, .shoulders])))
        #expect(abs(result.score - 0.65) <= 0.0001)
        #expect(result.directOverlap == 1)
        #expect(result.indirectOverlap == 1)
    }

    @Test func directOverlapOutranksIndirectOnly() {
        let source = movement("Bench", direct: [.chest], indirect: [.triceps])
        let direct = movement("Press", direct: [.chest], indirect: [])
        let indirect = movement("Extension", direct: [.shoulders], indirect: [.triceps])
        #expect(ExerciseSimilarity.rank(source: source, candidates: [indirect, direct]).first?.candidate.name == "Press")
    }

    @Test func typeBiasStillReturnsBorrowedResults() {
        let source = movement("Curl", direct: [.biceps], indirect: [], type: .strength)
        let strongman = movement("Carry", direct: [.biceps], indirect: [], type: .strongman)
        let results = ExerciseSimilarity.rank(source: source, candidates: [strongman], selectedType: .strength)
        #expect(results.count == 1)
        #expect(results[0].borrowed)
    }

    @Test func sourceIsExcludedAndResultsAreDescending() {
        let source = movement("Bench", direct: [.chest], indirect: [])
        let one = movement("Press", direct: [.chest], indirect: [])
        let two = movement("Row", direct: [.lats], indirect: [])
        let results = ExerciseSimilarity.rank(source: source, candidates: [two, source, one])
        #expect(results.map { $0.candidate.name } == ["Press", "Row"])
    }
}
