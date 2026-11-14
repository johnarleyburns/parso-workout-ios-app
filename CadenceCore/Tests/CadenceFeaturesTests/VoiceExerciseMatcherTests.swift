import XCTest
@testable import CadenceFeatures

final class VoiceExerciseMatcherTests: XCTestCase {
    func testExact() {
        XCTAssertEqual(VoiceExerciseMatcher.match("back squat", candidates: ["Front Squat", "Back Squat"]),
                       .exact("Back Squat"))
    }

    func testSquadInferredToSoleSquat() {
        let m = VoiceExerciseMatcher.match("squad", candidates: ["Squat"])
        XCTAssertEqual(m, .inferred("Squat"))
        XCTAssertTrue(m.isInferred)
    }

    func testNormalization() {
        XCTAssertEqual(VoiceExerciseMatcher.match("  BÉNCH-Press! ", candidates: ["Bench Press"]),
                       .exact("Bench Press"))
    }

    func testUniquePrefix() {
        XCTAssertEqual(VoiceExerciseMatcher.match("bench", candidates: ["Bench Press", "Pull Ups"]),
                       .inferred("Bench Press"))
    }

    func testSquadWithTiedCandidatesIsAmbiguous() {
        let m = VoiceExerciseMatcher.match("squad", candidates: ["Back Squat", "Front Squat"])
        XCTAssertNil(m.selected)
        XCTAssertEqual(m, .ambiguous(["Back Squat", "Front Squat"]))
    }

    func testUnrelatedIsNone() {
        XCTAssertEqual(VoiceExerciseMatcher.match("banana", candidates: ["Back Squat", "Bench Press"]), .none)
        XCTAssertEqual(VoiceExerciseMatcher.match("", candidates: ["Squat"]), .none)
    }

    func testOrderIndependent() {
        let names = ["Front Squat", "Back Squat", "Squat Jump"]
        for term in ["squad", "squat", "back squad", "front"] {
            XCTAssertEqual(VoiceExerciseMatcher.match(term, candidates: names),
                           VoiceExerciseMatcher.match(term, candidates: names.reversed()))
        }
    }
}
