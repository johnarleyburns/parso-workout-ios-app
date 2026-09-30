import XCTest
@testable import CadenceFeatures

final class VoiceModelFallbackTests: XCTestCase {
    private struct FakeInterpreter: VoiceModelInterpreting {
        let result: ModelVoiceCommand?

        func interpret(_ phrase: String, context: VoiceModelContext) async -> ModelVoiceCommand? {
            XCTAssertEqual(phrase, "put me down for another round")
            XCTAssertEqual(context.currentExercise, "Cable Face Pull")
            return result
        }
    }

    func testModelLogSetMapsToInferredCommand() {
        let parsed = VoiceModelCommandMapper.parse(ModelVoiceCommand(
            kind: .logSet, exercise: "Cable Face Pull", performer: "Me",
            weightKg: 25.85, reps: 8))

        XCTAssertEqual(parsed?.confidence, .inferred)
        XCTAssertEqual(parsed?.command, .logSet(VoiceSetSpec(
            exercise: VoiceExerciseRef(name: "Cable Face Pull"), weightKg: 25.85,
            reps: 8, performer: VoicePerformerRef(name: "Me"))))
    }

    func testInvalidModelNumbersAreRejected() {
        XCTAssertNil(VoiceModelCommandMapper.parse(ModelVoiceCommand(
            kind: .logSet, exercise: "Bench Press", reps: 101)))
        XCTAssertNil(VoiceModelCommandMapper.parse(ModelVoiceCommand(
            kind: .adjustNext, adjustKg: .infinity)))
        XCTAssertNil(VoiceModelCommandMapper.parse(ModelVoiceCommand(
            kind: .addExercise, exercise: "")))
    }

    func testFallbackDoesNotReplaceAnExactParserResult() async {
        let original = VoiceParseResult(command: .undo, confidence: .exact)
        let enhanced = await VoiceModelFallback.enhance(
            original, phrase: "undo",
            context: VoiceModelContext(currentExercise: nil, exercises: [], performers: []),
            interpreter: FakeInterpreter(result: ModelVoiceCommand(kind: .finishWorkout)))

        XCTAssertEqual(enhanced, original)
    }

    func testFallbackMapsOnlyValidModelOutput() async {
        let parsed = VoiceParseResult(command: nil, confidence: .ambiguous,
                                      clarification: "Try again")
        let enhanced = await VoiceModelFallback.enhance(
            parsed, phrase: "put me down for another round",
            context: VoiceModelContext(currentExercise: "Cable Face Pull",
                                       exercises: ["Cable Face Pull"], performers: ["Me"]),
            interpreter: FakeInterpreter(result: ModelVoiceCommand(
                kind: .repeatLastSet, performer: "Me", adjustKg: 2.5)))

        XCTAssertEqual(enhanced.confidence, .inferred)
        XCTAssertEqual(enhanced.command, .repeatLastSet(
            performer: VoicePerformerRef(name: "Me"),
            adjust: VoiceAdjust(deltaKg: 2.5)))
    }

    func testFallbackFailsClosedForInvalidOutput() async {
        let parsed = VoiceParseResult(command: nil, confidence: .ambiguous,
                                      clarification: "Try again")
        let enhanced = await VoiceModelFallback.enhance(
            parsed, phrase: "put me down for another round",
            context: VoiceModelContext(currentExercise: "Cable Face Pull",
                                       exercises: ["Cable Face Pull"], performers: ["Me"]),
            interpreter: FakeInterpreter(result: ModelVoiceCommand(
                kind: .logSet, exercise: "Cable Face Pull", reps: 0)))

        XCTAssertEqual(enhanced, parsed)
    }
}
