import Foundation
import Testing
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct IntervalInactivityEvidenceAdapterTests {
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

    @Test func runningRunnerNeverInactive() {
        #expect(decide(runner(started: true), at: t0.addingTimeInterval(3 * 3600)) == .continueRunning)
    }

    @Test func stalledRunnerAutoPausesAtTenMinutesThenEnds() {
        let r = runner(started: false)
        #expect(decide(r, at: t0.addingTimeInterval(599)) == .continueRunning)
        let pauseAt = t0.addingTimeInterval(600)
        #expect(decide(r, at: pauseAt) == .autoPause(at: pauseAt))
        let end = CardioInactivityPolicy.terminalDeadline(autoPausedAt: pauseAt)
        #expect(decide(r, origin: .automatic, autoPausedAt: pauseAt, at: end.addingTimeInterval(-1)) == .continuePaused)
        #expect(decide(r, origin: .automatic, autoPausedAt: pauseAt, at: end) == .autoEnd(at: end))
    }

    @Test func manualPauseNeverEnds() {
        let r = runner(started: true)
        r.pause()
        #expect(r.isPaused)
        #expect(decide(r, origin: .manual, at: t0.addingTimeInterval(10 * 3600)) == .continuePaused)
    }

    @Test func resumeClearsTerminalDeadline() {
        var s = CardioInactivityState()
        s.recordAutoPause(at: t0)
        #expect(s.autoEndDeadline != nil)
        s.recordResume(at: t0.addingTimeInterval(60))
        #expect(s.autoEndDeadline == nil)
    }
}
