import Foundation
import Testing
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct CardioInactivityPolicyTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    private func decide(_ e: CardioActivityEvidence, _ s: TimeInterval, enabled: Bool = true) -> CardioInactivityDecision {
        CardioInactivityPolicy.decide(evidence: e, now: at(s), enabled: enabled)
    }

    @Test func runningBoundaries() {
        let e = CardioActivityEvidence(lastUserActionAt: t0)
        #expect(decide(e, 599) == .continueRunning)
        #expect(decide(e, 600) == .autoPause(at: at(600)))
        #expect(decide(e, 7200) == .autoPause(at: at(600)))
    }

    @Test func automaticPauseBoundaries() {
        let e = CardioActivityEvidence(pauseOrigin: .automatic, autoPausedAt: at(600))
        #expect(decide(e, 600 + 29 * 60 + 59) == .continuePaused)
        #expect(decide(e, 600 + 30 * 60) == .autoEnd(at: at(600 + 1800)))
        #expect(decide(e, 99_999) == .autoEnd(at: at(2400)))
    }

    @Test func eachEvidenceSourcePreventsPause() {
        for e in [CardioActivityEvidence(lastDistanceProgressAt: at(300)),
                  CardioActivityEvidence(lastMotionAt: at(300)),
                  CardioActivityEvidence(lastQualifyingHeartRateAt: at(300)),
                  CardioActivityEvidence(lastUserActionAt: at(300))] {
            #expect(decide(e, 899) == .continueRunning)
            #expect(decide(e, 900) == .autoPause(at: at(900)))
        }
    }

    @Test func sensorProfilesFilterEvidence() {
        let indoor = CardioActivityEvidence(lastDistanceProgressAt: at(500), lastMotionAt: at(500),
                                            referenceStartAt: t0, sensorProfile: .indoor)
        #expect(decide(indoor, 600) == .autoPause(at: at(600)))
        let timer = CardioActivityEvidence(lastQualifyingHeartRateAt: at(500), referenceStartAt: t0,
                                           sensorProfile: .timerOnly)
        #expect(decide(timer, 600) == .autoPause(at: at(600)))
    }

    @Test func heartRateQualification() {
        let now = at(1000)
        func q(_ bpm: Double, _ sample: TimeInterval, prev: Date? = nil, rest: Double? = nil) -> Bool {
            CardioInactivityPolicy.isQualifyingHeartRate(bpm: bpm, sampleAt: at(sample), receivedAt: now,
                                                         previousQualifyingAt: prev, restingHeartRate: rest)
        }
        #expect(q(120, 990))
        #expect(!q(120, 900))            // stale
        #expect(!q(70, 990))             // low
        #expect(!q(120, 990, prev: at(990))) // replay/duplicate
        #expect(!q(100, 990, rest: 90))  // not above resting
    }

    @Test func plannedIntervalNeverActs() {
        let e = CardioActivityEvidence(lastUserActionAt: t0, isInPlannedIntervalPhase: true)
        #expect(decide(e, 100_000) == .continueRunning)
    }

    @Test func manualPauseNeverEnds() {
        let e = CardioActivityEvidence(pauseOrigin: .manual, autoPausedAt: at(0))
        #expect(decide(e, 1_000_000) == .continuePaused)
    }

    @Test func disabledNeverActs() {
        #expect(decide(CardioActivityEvidence(lastUserActionAt: t0), 100_000, enabled: false) == .continueRunning)
        #expect(decide(CardioActivityEvidence(pauseOrigin: .automatic, autoPausedAt: t0), 100_000, enabled: false) == .continuePaused)
    }

    @Test func resumeClearsTerminalDeadline() {
        var s = CardioInactivityState()
        s.recordAutoPause(at: at(600))
        #expect(s.autoEndDeadline == at(2400))
        s.recordResume(at: at(900))
        #expect(s.autoEndDeadline == nil); #expect(s.pauseOrigin == nil)
        let e = CardioActivityEvidence(lastUserActionAt: at(900))
        #expect(decide(e, 1499) == .continueRunning)
        s.recordManualPause(at: at(1000))
        #expect(s.pauseOrigin == .manual); #expect(s.autoEndDeadline == nil)
    }

    @Test func repeatedAndJumpedClocksKeepDeadlines() {
        let e = CardioActivityEvidence(lastUserActionAt: t0)
        #expect(decide(e, 700) == decide(e, 90_000))
        let p = CardioActivityEvidence(pauseOrigin: .automatic, autoPausedAt: at(600))
        #expect(decide(p, 2400) == decide(p, 500_000))
        #expect(decide(e, -5000) == .continueRunning)
    }

    @Test func stateBackwardCompatibleCodable() throws {
        let s = try JSONDecoder().decode(CardioInactivityState.self, from: Data("{}".utf8))
        #expect(s == CardioInactivityState())
    }

    @Test func cardioDefaultsEnableAutoPauseAndOptOutPersists() throws {
        #expect(WorkoutSettings.cardioDefault.autoPause)
        var off = WorkoutSettings.cardioDefault; off.autoPause = false
        let back = try JSONDecoder().decode(WorkoutSettings.self, from: JSONEncoder().encode(off))
        #expect(!back.autoPause)
    }
}
