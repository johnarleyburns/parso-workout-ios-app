import XCTest
@testable import CadenceFeatures

final class SpeechVocabularyTests: XCTestCase {
    private final class FakeRequest: ContextualStringsConfigurable {
        var contextualStrings: [String] = []
    }

    func testCurrentExerciseFirstAndStableOrder() {
        let v = SpeechVocabulary.exerciseVocabulary(current: "Squat", exercises: ["Bench Press", "Squat", "Row"])
        XCTAssertEqual(v, ["Squat", "Bench Press", "Row"])
    }

    func testDuplicatesAndBlanksRemoved() {
        let v = SpeechVocabulary.exerciseVocabulary(current: " Row ", exercises: ["", "  ", "Row", "Curl", "Curl "])
        XCTAssertEqual(v, ["Row", "Curl"])
    }

    func testLimitEnforced() {
        let names = (0..<100).map { "Ex \($0)" }
        let v = SpeechVocabulary.exerciseVocabulary(current: "Ex 50", exercises: names)
        XCTAssertEqual(v.count, SpeechVocabulary.maxCount)
        XCTAssertEqual(v.first, "Ex 50")
    }

    func testEmptyWorkoutIsEmpty() {
        XCTAssertEqual(SpeechVocabulary.exerciseVocabulary(current: nil, exercises: []), [])
    }

    func testSquatIncludedWhenActive() {
        XCTAssertTrue(SpeechVocabulary.exerciseVocabulary(current: nil, exercises: ["Squat"]).contains("Squat"))
    }

    func testRequestReceivesHelperOutput() {
        let r = FakeRequest()
        let v = SpeechVocabulary.exerciseVocabulary(current: "Squat", exercises: ["Row"])
        SpeechVocabulary.apply(v, to: r)
        XCTAssertEqual(r.contextualStrings, ["Squat", "Row"])
    }
}
