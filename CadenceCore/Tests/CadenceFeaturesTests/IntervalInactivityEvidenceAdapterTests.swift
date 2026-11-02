import XCTest
import CadenceCore
@testable import CadenceFeatures

final class IntervalInactivityEvidenceAdapterTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func runner(started: Bool) -> CombinedPlanRunner {
        // swiftlint:disable:next force_try
        let plan = try! CombinedExecutionPlan(session: Session(title: "Intervals", items: [
            .cardio(CardioItem(id: UUID(), order: 0,
                               prescription: .steadyState(SteadyState(
                                activity: .run, durationSeconds: 3600))))
        ]))
        let r = CombinedPlanRunner(plan: plan)
        if started { r.start(now: t0) }
        return r
    }

    private func decide(_ r: CombinedPlanRunner, origin: CardioPauseOrigin? = nil,
                        autoPausedAt: Date? = nil, at now: Date) -> CardioInactivityDecision {
        let e = IntervalInactivityEvidenceAdapter.evidence(
            runner: r, lastUserActionAt: t0, lastSensorEvidenceAt: nil,
            pauseOrigin: origin, autoPausedAt: autoPausedAt)
        return CardioInactivityPolicy.decide(evidence: e, now: now, enabled: true)
    }

    func testRunningRunnerNeverInactive() {
        XCTAssertEqual(decide(runner(started: true), at: t0.addingTimeInterval(3 * 3600)), .continueRunning)
    }

    func testStalledRunnerAutoPausesAtTenMinutesThenEnds() {
        let r = runner(started: false)
        XCTAssertEqual(decide(r, at: t0.addingTimeInterval(599)), .continueRunning)
        let pauseAt = t0.addingTimeInterval(600)
        XCTAssertEqual(decide(r, at: pauseAt), .autoPause(at: pauseAt))
        let end = CardioInactivityPolicy.terminalDeadline(autoPausedAt: pauseAt)
        XCTAssertEqual(decide(r, origin: .automatic, autoPausedAt: pauseAt, at: end.addingTimeInterval(-1)), .continuePaused)
        XCTAssertEqual(decide(r, origin: .automatic, autoPausedAt: pauseAt, at: end), .autoEnd(at: end))
    }

    func testManualPauseNeverEnds() {
        let r = runner(started: true)
        r.pause()
        XCTAssertTrue(r.isPaused)
        XCTAssertEqual(decide(r, origin: .manual, at: t0.addingTimeInterval(10 * 3600)), .continuePaused)
    }

    func testResumeClearsTerminalDeadline() {
        var s = CardioInactivityState()
        s.recordAutoPause(at: t0)
        XCTAssertNotNil(s.autoEndDeadline)
        s.recordResume(at: t0.addingTimeInterval(60))
        XCTAssertNil(s.autoEndDeadline)
    }
}
