import XCTest
import CadenceCore
@testable import CadenceFeatures

final class VoiceCommandResolverTests: XCTestCase {
    private let exercises = ["Bench Press", "Cable Face Pull", "Pull Ups"]
    private let performers = ["Me", "Audrey", "Sam"]

    func testResolvesExplicitPartnerSetWithoutChangingExerciseContext() {
        let parsed = VoiceCommandParser.parse("audrey did 20 reps at 57 pounds")
        let result = VoiceCommandResolver.resolve(parsed, currentExercise: "Bench Press",
                                                  exercises: exercises, performers: performers)
        guard case .logSet(let exercise, let weightKg, let reps, _, _, let performer) = result.action else {
            return XCTFail("Expected resolved log action")
        }
        XCTAssertEqual(exercise.name, "Bench Press")
        XCTAssertEqual(weightKg ?? 0, WorkoutMath.lbToKg(57), accuracy: 0.0001)
        XCTAssertEqual(reps, 20)
        XCTAssertEqual(performer.name, "Audrey")
        XCTAssertFalse(performer.isOwner)
    }

    func testRepeatUsesActivePartnerInsteadOfOwner() {
        let parsed = VoiceCommandParser.parse("same again")
        let result = VoiceCommandResolver.resolve(parsed, currentExercise: "Cable Face Pull",
                                                  exercises: exercises, performers: performers,
                                                  activePerformer: "Sam")
        guard case .repeatLastSet(let exercise, let performer, _) = result.action else {
            return XCTFail("Expected repeat action")
        }
        XCTAssertEqual(exercise.name, "Cable Face Pull")
        XCTAssertEqual(performer.name, "Sam")
        XCTAssertFalse(performer.isOwner)
    }

    func testMissingExerciseIsNotSilentlyGuessed() {
        let parsed = VoiceCommandParser.parse("same again")
        let result = VoiceCommandResolver.resolve(parsed, currentExercise: nil,
                                                  exercises: exercises, performers: performers)
        XCTAssertNil(result.action)
        XCTAssertEqual(result.issue, .missingExercise)
    }

    func testExercisePrefixCanResolveUniquely() {
        let parsed = VoiceCommandParser.parse("pull ups for ten reps", bodyweight: true)
        let result = VoiceCommandResolver.resolve(parsed, currentExercise: nil,
                                                  exercises: exercises, performers: performers)
        guard case .logSet(let exercise, _, let reps, _, _, _) = result.action else {
            return XCTFail("Expected resolved bodyweight action")
        }
        XCTAssertEqual(exercise.name, "Pull Ups")
        XCTAssertEqual(reps, 10)
    }
}
