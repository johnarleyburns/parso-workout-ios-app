import XCTest
import CadenceCore
@testable import CadenceFeatures

final class VoiceCommandParserTests: XCTestCase {
    func testPartnerPhraseUsesExplicitRepAndWeightKeywords() {
        let result = VoiceCommandParser.parse("audrey did twenty reps at twenty pounds")
        guard case .logSet(let spec) = result.command else { return XCTFail("Expected log command") }
        XCTAssertEqual(spec.performer?.name, "Audrey")
        XCTAssertEqual(spec.reps, 20)
        XCTAssertEqual(spec.weightKg ?? 0, WorkoutMath.lbToKg(20), accuracy: 0.0001)
        XCTAssertEqual(result.confidence, .exact)
    }

    func testGymNumberWordsNormalizeTwoTwentyFive() {
        let result = VoiceCommandParser.parse("bench press two twenty five for five")
        guard case .logSet(let spec) = result.command else { return XCTFail("Expected log command") }
        XCTAssertEqual(spec.exercise?.name, "bench press")
        XCTAssertEqual(spec.reps, 5)
        XCTAssertEqual(spec.weightKg ?? 0, WorkoutMath.lbToKg(225), accuracy: 0.0001)
    }

    func testKilogramsWinOverPreference() {
        let result = VoiceCommandParser.parse("deadlift 100 kg for 3", unit: .pounds)
        guard case .logSet(let spec) = result.command else { return XCTFail("Expected log command") }
        XCTAssertEqual(spec.weightKg ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(spec.reps, 3)
        XCTAssertEqual(result.confidence, .exact)
    }

    func testBodyweightKeepsOnlyReps() {
        let result = VoiceCommandParser.parse("pull ups for ten reps", bodyweight: true)
        guard case .logSet(let spec) = result.command else { return XCTFail("Expected log command") }
        XCTAssertNil(spec.weightKg)
        XCTAssertEqual(spec.reps, 10)
    }

    func testCommands() {
        XCTAssertEqual(VoiceCommandParser.parse("same again").command,
                       .repeatLastSet(performer: nil, adjust: nil))
        XCTAssertEqual(VoiceCommandParser.parse("plus five pounds").command,
                       .adjustNext(VoiceAdjust(deltaKg: WorkoutMath.lbToKg(5))))
        XCTAssertEqual(VoiceCommandParser.parse("rest two minutes").command, .rest(seconds: 120))
        XCTAssertEqual(VoiceCommandParser.parse("undo").command, .undo)
        XCTAssertEqual(VoiceCommandParser.parse("add face pulls").command,
                       .addExercise(VoiceExerciseRef(name: "face pulls")))
    }

    func testMissingNumbersDoesNotGuess() {
        let result = VoiceCommandParser.parse("bench press")
        XCTAssertNil(result.command)
        XCTAssertEqual(result.confidence, .ambiguous)
        XCTAssertNotNil(result.clarification)
    }
}
