import Foundation
import Testing
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct CombinedPlanRunnerTests {
    @Test func planPreservesCardioAndMobilityOrderAndRejectsStrength() throws {
        let cardioID = UUID()
        let mobilityID = UUID()
        let plan = try CombinedExecutionPlan(session: Session(title: "Conditioning", items: [
            .cardio(CardioItem(id: cardioID, order: 0,
                               prescription: .steadyState(SteadyState(
                                activity: .run, durationSeconds: 10)))),
            .mobility(MobilityItem(id: mobilityID, order: 1, name: "Couch stretch",
                                    perRound: .duration(seconds: 30)))
        ]))

        #expect(plan.steps.map(\.id) == [cardioID, mobilityID])
        #expect(plan.steps.first?.timedDurationSeconds == 10)
        #expect(plan.steps.last?.timedDurationSeconds == nil)

        #expect(throws: CombinedExecutionPlan.Error.unsupportedBoundary(.strengthOnly)) {
            try CombinedExecutionPlan(session: Session(
                title: "Strength", items: [.strength(StrengthItem(
                    exerciseKey: ExerciseKey(raw: "back_squat"), order: 0))]))
        }
    }

    @Test func timedCardioAutoAdvancesAndMobilityRequiresExplicitCompletion() throws {
        let plan = try CombinedExecutionPlan(session: Session(title: "Intervals", items: [
            .cardio(CardioItem(order: 0, prescription: .steadyState(SteadyState(
                activity: .bike, durationSeconds: 5)))),
            .mobility(MobilityItem(order: 1, name: "Breathing", perRound: .duration(seconds: 20)))
        ]))
        let runner = CombinedPlanRunner(plan: plan)
        let start = Date(timeIntervalSince1970: 100)

        runner.start(now: start)
        runner.tick(seconds: 4)
        #expect(runner.currentStepIndex == 0)
        #expect(runner.elapsedSeconds == 4)
        runner.tick(seconds: 1)
        #expect(runner.currentStepIndex == 1)
        #expect(runner.completedStepIDs == [plan.steps[0].id])
        #expect(runner.state == .running)

        runner.tick(seconds: 20)
        #expect(runner.currentStepIndex == 1)
        #expect(runner.state == .running)
        runner.completeCurrentStep()
        #expect(runner.isComplete)
        #expect(runner.completedStepIDs == plan.steps.map(\.id))
        #expect(runner.endedAt == start.addingTimeInterval(25))
    }

    @Test func pauseFreezesClockAndFinishCapturesPartialStep() throws {
        let plan = try CombinedExecutionPlan(session: Session(title: "Mobility", items: [
            .mobility(MobilityItem(order: 0, name: "Hips", perRound: .duration(seconds: 30)))
        ]))
        let runner = CombinedPlanRunner(plan: plan)
        let start = Date(timeIntervalSince1970: 200)

        runner.start(now: start)
        runner.tick(seconds: 7)
        runner.pause()
        runner.tick(seconds: 100)
        #expect(runner.elapsedSeconds == 7)
        #expect(runner.state == .paused)

        #expect(runner.finish(now: start.addingTimeInterval(11)))
        #expect(runner.state == .finished)
        #expect(runner.completedStepIDs == [plan.steps[0].id])
        #expect(runner.endedAt == start.addingTimeInterval(11))
    }

    @Test func intervalTimingIncludesWarmupWorkRecoveryAndCooldown() throws {
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

        #expect(plan.steps.first?.timedDurationSeconds == 27)
        #expect(plan.timedDurationSeconds == 27)
    }
}
