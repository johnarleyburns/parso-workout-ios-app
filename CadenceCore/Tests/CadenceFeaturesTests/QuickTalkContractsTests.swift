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
