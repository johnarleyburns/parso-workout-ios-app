import XCTest
@testable import CadenceCore

final class PlanExecutionBoundaryTests: XCTestCase {
    func testEmptySessionHasNoExecutionRunner() {
        let session = Session(title: "Empty")

        XCTAssertEqual(session.executionBoundary, .empty)
        XCTAssertFalse(session.executionBoundary.canStartStrengthRunner)
        XCTAssertFalse(session.executionBoundary.canProjectToWatch)
    }

    func testStrengthOnlySessionKeepsTheExistingRunnerBoundary() {
        let session = Session(title: "Strength", items: [.strength(strengthItem())])

        XCTAssertEqual(session.executionBoundary, .strengthOnly)
        XCTAssertTrue(session.executionBoundary.canStartStrengthRunner)
        XCTAssertTrue(session.executionBoundary.canProjectToWatch)
    }

    func testCardioOnlySessionProjectsToWatchButNotStrengthRunner() {
        let session = Session(title: "Run", items: [.cardio(cardioItem())])

        XCTAssertEqual(session.executionBoundary, .cardioOnly)
        XCTAssertFalse(session.executionBoundary.canStartStrengthRunner)
        XCTAssertTrue(session.executionBoundary.canStartCombinedRunner)
        XCTAssertTrue(session.executionBoundary.canProjectToWatch)
    }

    func testMobilityAndInstructionRemainSavedButNotExecutable() {
        let mobility = Session(title: "Mobility", items: [
            .mobility(MobilityItem(order: 0, name: "Hip opener", perRound: .duration(seconds: 30)))
        ])
        let instruction = Session(title: "Notes", items: [
            .instruction(InstructionItem(order: 0, text: "Breathe slowly."))
        ])

        XCTAssertEqual(mobility.executionBoundary, .mobilityOnly)
        XCTAssertEqual(instruction.executionBoundary, .instructionOnly)
        XCTAssertTrue(mobility.executionBoundary.canStartCombinedRunner)
        XCTAssertFalse(instruction.executionBoundary.canStartCombinedRunner)
        XCTAssertFalse(mobility.executionBoundary.canProjectToWatch)
        XCTAssertFalse(instruction.executionBoundary.canProjectToWatch)
    }

    func testCardioMobilitySessionUsesCombinedRunnerBoundary() {
        let session = Session(title: "Run and recover", items: [
            .cardio(CardioItem(order: 0, prescription: .steadyState(SteadyState(
                activity: .run, durationSeconds: 1_800)))),
            .mobility(MobilityItem(order: 1, name: "Hip opener", perRound: .duration(seconds: 30)))
        ])

        XCTAssertEqual(session.executionBoundary,
                       .mixed([.cardio, .mobility]))
        XCTAssertTrue(session.executionBoundary.canStartCombinedRunner)
        XCTAssertFalse(session.executionBoundary.canStartStrengthRunner)
        XCTAssertFalse(session.executionBoundary.canProjectToWatch)
    }

    func testMixedSessionCannotBeMisclassifiedAsStrengthOrWatchExecutable() {
        let session = Session(title: "Lift and run", items: [
            .strength(strengthItem()),
            .cardio(cardioItem()),
            .instruction(InstructionItem(order: 2, text: "Cool down."))
        ])

        XCTAssertEqual(session.executionBoundary,
                       .mixed([.strength, .cardio, .instruction]))
        XCTAssertFalse(session.executionBoundary.canStartStrengthRunner)
        XCTAssertFalse(session.executionBoundary.canProjectToWatch)
    }

    private func strengthItem() -> StrengthItem {
        StrengthItem(
            exerciseKey: ExerciseKey(raw: "back_squat"),
            order: 0,
            sets: [PrescribedSet(setIndex: 0, repTarget: .exact(5))])
    }

    private func cardioItem() -> CardioItem {
        CardioItem(
            order: 1,
            prescription: .steadyState(SteadyState(
                activity: .run, durationSeconds: 1_800)))
    }
}
