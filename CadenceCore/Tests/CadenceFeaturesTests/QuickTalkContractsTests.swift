import XCTest
@testable import CadenceFeatures

final class QuickTalkContractsTests: XCTestCase {
    func testOnlyExactSetLogsAutoExecute() {
        let action = VoiceResolvedAction.logSet(
            exercise: VoiceResolvedExercise(name: "Bench Press"), weightKg: 57,
            reps: 8, rpe: nil, isWarmup: false,
            performer: VoiceResolvedPerformer(name: "Me", isOwner: true))
        let resolver = VoiceCommandExecutor()
        let exact = VoiceParseResult(command: .logSet(VoiceSetSpec(
            exercise: VoiceExerciseRef(name: "Bench Press"), weightKg: 57, reps: 8)),
                                      confidence: .exact)
        XCTAssertEqual(resolver.automaticAction(parsed: exact,
                                                 resolution: VoiceResolutionResult(action: action)), action)
        let inferred = VoiceParseResult(command: exact.command, confidence: .inferred)
        XCTAssertNil(resolver.automaticAction(parsed: inferred,
                                               resolution: VoiceResolutionResult(action: action)))
    }

    private func resolveSet(_ name: String, exercises: [String]) -> (VoiceParseResult, VoiceResolutionResult) {
        let parsed = VoiceParseResult(command: .logSet(VoiceSetSpec(
            exercise: VoiceExerciseRef(name: name), weightKg: 100, reps: 5)), confidence: .exact)
        let r = VoiceEntityResolver().resolve(parsed, currentExercise: nil,
                                              exercises: exercises, performers: ["Me"])
        return (parsed, r)
    }

    func testNearExerciseMatchResolvesButIsNotAutomatic() {
        let (parsed, r) = resolveSet("squad", exercises: ["Squat"])
        guard case .logSet(let ex, _, _, _, _, _)? = r.action else { return XCTFail("no action") }
        XCTAssertEqual(ex.name, "Squat")
        XCTAssertTrue(r.exerciseWasInferred)
        XCTAssertNil(VoiceCommandExecutor().automaticAction(parsed: parsed, resolution: r))
    }

    func testExactExerciseRemainsAutomatic() {
        let (parsed, r) = resolveSet("squat", exercises: ["Squat"])
        XCTAssertFalse(r.exerciseWasInferred)
        XCTAssertNotNil(VoiceCommandExecutor().automaticAction(parsed: parsed, resolution: r))
    }

    func testAmbiguousNearExerciseProducesNoAction() {
        let (_, r) = resolveSet("squad", exercises: ["Back Squat", "Front Squat"])
        XCTAssertNil(r.action)
        XCTAssertNotNil(r.clarification)
    }

    func testHeardLogIsBoundedAndFollowUpExpiresAtEightSeconds() {
        var log = HeardVoiceLog(capacity: 2)
        for index in 0..<3 {
            log.append(HeardVoiceEntry(transcript: "set \(index)", confidence: .exact,
                                       appliedAutomatically: true))
        }
        XCTAssertEqual(log.entries.map(\.transcript), ["set 1", "set 2"])

        let start = Date(timeIntervalSince1970: 100)
        let window = QuickTalkFollowUpWindow(startedAt: start)
        XCTAssertTrue(window.accepts(start.addingTimeInterval(8)))
        XCTAssertFalse(window.accepts(start.addingTimeInterval(8.001)))
    }

    func testVoiceCaptureStartGateRejectsConcurrentStarts() {
        var gate = VoiceCaptureStartGate()
        XCTAssertTrue(gate.begin())
        XCTAssertFalse(gate.begin())
        gate.finish()
        XCTAssertTrue(gate.begin())
    }
}
