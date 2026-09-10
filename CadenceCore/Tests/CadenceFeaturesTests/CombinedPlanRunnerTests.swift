import XCTest
import CadenceCore
@testable import CadenceFeatures

final class CombinedPlanRunnerTests: XCTestCase {
    func testPlanPreservesCardioAndMobilityOrderAndRejectsStrength() throws {
        let cardioID = UUID()
        let mobilityID = UUID()
        let plan = try CombinedExecutionPlan(session: Session(title: "Conditioning", items: [
            .cardio(CardioItem(id: cardioID, order: 0,
                               prescription: .steadyState(SteadyState(
                                activity: .run, durationSeconds: 10)))),
            .mobility(MobilityItem(id: mobilityID, order: 1, name: "Couch stretch",
                                    perRound: .duration(seconds: 30)))
        ]))

        XCTAssertEqual(plan.steps.map(\.id), [cardioID, mobilityID])
        XCTAssertEqual(plan.steps.first?.timedDurationSeconds, 10)
        XCTAssertEqual(plan.steps.last?.timedDurationSeconds, nil)

        XCTAssertThrowsError(try CombinedExecutionPlan(session: Session(
            title: "Strength", items: [.strength(StrengthItem(
                exerciseKey: ExerciseKey(raw: "back_squat"), order: 0))]))) { error in
            guard case .unsupportedBoundary(.strengthOnly) = error as? CombinedExecutionPlan.Error else {
                return XCTFail("Expected the strength-only boundary")
            }
        }
    }

    func testTimedCardioAutoAdvancesAndMobilityRequiresExplicitCompletion() throws {
        let plan = try CombinedExecutionPlan(session: Session(title: "Intervals", items: [
            .cardio(CardioItem(order: 0, prescription: .steadyState(SteadyState(
                activity: .bike, durationSeconds: 5)))),
            .mobility(MobilityItem(order: 1, name: "Breathing", perRound: .duration(seconds: 20)))
        ]))
        let runner = CombinedPlanRunner(plan: plan)
        let start = Date(timeIntervalSince1970: 100)

        runner.start(now: start)
        runner.tick(seconds: 4)
        XCTAssertEqual(runner.currentStepIndex, 0)
        XCTAssertEqual(runner.elapsedSeconds, 4)
        runner.tick(seconds: 1)
        XCTAssertEqual(runner.currentStepIndex, 1)
        XCTAssertEqual(runner.completedStepIDs, [plan.steps[0].id])
        XCTAssertEqual(runner.state, .running)

        runner.tick(seconds: 20)
        XCTAssertEqual(runner.currentStepIndex, 1)
        XCTAssertEqual(runner.state, .running)
        runner.completeCurrentStep()
        XCTAssertTrue(runner.isComplete)
        XCTAssertEqual(runner.completedStepIDs, plan.steps.map(\.id))
        XCTAssertEqual(runner.endedAt, start.addingTimeInterval(25))
    }

    func testPauseFreezesClockAndFinishCapturesPartialStep() throws {
        let plan = try CombinedExecutionPlan(session: Session(title: "Mobility", items: [
            .mobility(MobilityItem(order: 0, name: "Hips", perRound: .duration(seconds: 30)))
        ]))
        let runner = CombinedPlanRunner(plan: plan)
        let start = Date(timeIntervalSince1970: 200)

        runner.start(now: start)
        runner.tick(seconds: 7)
        runner.pause()
        runner.tick(seconds: 100)
        XCTAssertEqual(runner.elapsedSeconds, 7)
        XCTAssertEqual(runner.state, .paused)

        XCTAssertTrue(runner.finish(now: start.addingTimeInterval(11)))
        XCTAssertEqual(runner.state, .finished)
        XCTAssertEqual(runner.completedStepIDs, [plan.steps[0].id])
        XCTAssertEqual(runner.endedAt, start.addingTimeInterval(11))
    }

    func testIntervalTimingIncludesWarmupWorkRecoveryAndCooldown() throws {
        let intervals = Intervals(
            activity: .row,
            warmupSeconds: 3,
            rounds: 2,
            work: IntervalSegment(durationSeconds: 5, intensity: .rpe(7...8)),
            recovery: IntervalSegment(durationSeconds: 4, intensity: .rpe(2...3)),
            cooldownSeconds: 6)
        let plan = try CombinedExecutionPlan(session: Session(title: "Row intervals", items: [
            .cardio(CardioItem(order: 0, prescription: .intervals(intervals)))
        ]))

        XCTAssertEqual(plan.steps.first?.timedDurationSeconds, 27)
        XCTAssertEqual(plan.timedDurationSeconds, 27)
    }
}
