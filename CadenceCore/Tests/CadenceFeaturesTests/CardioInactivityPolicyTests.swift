import XCTest
import CadenceCore
@testable import CadenceFeatures

final class CardioInactivityPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    private func decide(_ e: CardioActivityEvidence, _ s: TimeInterval, enabled: Bool = true) -> CardioInactivityDecision {
        CardioInactivityPolicy.decide(evidence: e, now: at(s), enabled: enabled)
    }

    func testRunningBoundaries() {
        let e = CardioActivityEvidence(lastUserActionAt: t0)
        XCTAssertEqual(decide(e, 599), .continueRunning)
        XCTAssertEqual(decide(e, 600), .autoPause(at: at(600)))
        XCTAssertEqual(decide(e, 7200), .autoPause(at: at(600)))
    }

    func testAutomaticPauseBoundaries() {
        let e = CardioActivityEvidence(pauseOrigin: .automatic, autoPausedAt: at(600))
        XCTAssertEqual(decide(e, 600 + 29 * 60 + 59), .continuePaused)
        XCTAssertEqual(decide(e, 600 + 30 * 60), .autoEnd(at: at(600 + 1800)))
        XCTAssertEqual(decide(e, 99_999), .autoEnd(at: at(2400)))
    }

    func testEachEvidenceSourcePreventsPause() {
        for e in [CardioActivityEvidence(lastDistanceProgressAt: at(300)),
                  CardioActivityEvidence(lastMotionAt: at(300)),
                  CardioActivityEvidence(lastQualifyingHeartRateAt: at(300)),
                  CardioActivityEvidence(lastUserActionAt: at(300))] {
            XCTAssertEqual(decide(e, 899), .continueRunning)
            XCTAssertEqual(decide(e, 900), .autoPause(at: at(900)))
        }
    }

    func testSensorProfilesFilterEvidence() {
        let indoor = CardioActivityEvidence(lastDistanceProgressAt: at(500), lastMotionAt: at(500),
                                            referenceStartAt: t0, sensorProfile: .indoor)
        XCTAssertEqual(decide(indoor, 600), .autoPause(at: at(600)))
        let timer = CardioActivityEvidence(lastQualifyingHeartRateAt: at(500), referenceStartAt: t0,
                                           sensorProfile: .timerOnly)
        XCTAssertEqual(decide(timer, 600), .autoPause(at: at(600)))
    }

    func testHeartRateQualification() {
        let now = at(1000)
        func q(_ bpm: Double, _ sample: TimeInterval, prev: Date? = nil, rest: Double? = nil) -> Bool {
            CardioInactivityPolicy.isQualifyingHeartRate(bpm: bpm, sampleAt: at(sample), receivedAt: now,
                                                         previousQualifyingAt: prev, restingHeartRate: rest)
        }
        XCTAssertTrue(q(120, 990))
        XCTAssertFalse(q(120, 900))            // stale
        XCTAssertFalse(q(70, 990))             // low
        XCTAssertFalse(q(120, 990, prev: at(990))) // replay/duplicate
        XCTAssertFalse(q(100, 990, rest: 90))  // not above resting
    }

    func testPlannedIntervalNeverActs() {
        let e = CardioActivityEvidence(lastUserActionAt: t0, isInPlannedIntervalPhase: true)
        XCTAssertEqual(decide(e, 100_000), .continueRunning)
    }

    func testManualPauseNeverEnds() {
        let e = CardioActivityEvidence(pauseOrigin: .manual, autoPausedAt: at(0))
        XCTAssertEqual(decide(e, 1_000_000), .continuePaused)
    }

    func testDisabledNeverActs() {
        XCTAssertEqual(decide(CardioActivityEvidence(lastUserActionAt: t0), 100_000, enabled: false), .continueRunning)
        XCTAssertEqual(decide(CardioActivityEvidence(pauseOrigin: .automatic, autoPausedAt: t0), 100_000, enabled: false), .continuePaused)
    }

    func testResumeClearsTerminalDeadline() {
        var s = CardioInactivityState()
        s.recordAutoPause(at: at(600))
        XCTAssertEqual(s.autoEndDeadline, at(2400))
        s.recordResume(at: at(900))
        XCTAssertNil(s.autoEndDeadline); XCTAssertNil(s.pauseOrigin)
        let e = CardioActivityEvidence(lastUserActionAt: at(900))
        XCTAssertEqual(decide(e, 1499), .continueRunning)
        s.recordManualPause(at: at(1000))
        XCTAssertEqual(s.pauseOrigin, .manual); XCTAssertNil(s.autoEndDeadline)
    }

    func testRepeatedAndJumpedClocksKeepDeadlines() {
        let e = CardioActivityEvidence(lastUserActionAt: t0)
        XCTAssertEqual(decide(e, 700), decide(e, 90_000))
        let p = CardioActivityEvidence(pauseOrigin: .automatic, autoPausedAt: at(600))
        XCTAssertEqual(decide(p, 2400), decide(p, 500_000))
        XCTAssertEqual(decide(e, -5000), .continueRunning)
    }

    func testStateBackwardCompatibleCodable() throws {
        let s = try JSONDecoder().decode(CardioInactivityState.self, from: Data("{}".utf8))
        XCTAssertEqual(s, CardioInactivityState())
    }

    func testCardioDefaultsEnableAutoPauseAndOptOutPersists() throws {
        XCTAssertTrue(WorkoutSettings.cardioDefault.autoPause)
        var off = WorkoutSettings.cardioDefault; off.autoPause = false
        let back = try JSONDecoder().decode(WorkoutSettings.self, from: JSONEncoder().encode(off))
        XCTAssertFalse(back.autoPause)
    }
}
