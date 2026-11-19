import Testing
@testable import CadenceCore

struct PlanExecutionBoundaryTests {
    @Test func emptySessionHasNoExecutionRunner() {
        let session = Session(title: "Empty")

        #expect(session.executionBoundary == .empty)
        #expect(!session.executionBoundary.canStartStrengthRunner)
        #expect(!session.executionBoundary.canProjectToWatch)
    }

    @Test func strengthOnlySessionKeepsTheExistingRunnerBoundary() {
        let session = Session(title: "Strength", items: [.strength(strengthItem())])

        #expect(session.executionBoundary == .strengthOnly)
        #expect(session.executionBoundary.canStartStrengthRunner)
        #expect(session.executionBoundary.canProjectToWatch)
    }

    @Test func cardioOnlySessionProjectsToWatchButNotStrengthRunner() {
        let session = Session(title: "Run", items: [.cardio(cardioItem())])

        #expect(session.executionBoundary == .cardioOnly)
        #expect(!session.executionBoundary.canStartStrengthRunner)
        #expect(session.executionBoundary.canStartCombinedRunner)
        #expect(session.executionBoundary.canProjectToWatch)
    }

    @Test func mobilityAndInstructionRemainSavedButNotExecutable() {
        let mobility = Session(title: "Mobility", items: [
            .mobility(MobilityItem(order: 0, name: "Hip opener", perRound: .duration(seconds: 30)))
        ])
        let instruction = Session(title: "Notes", items: [
            .instruction(InstructionItem(order: 0, text: "Breathe slowly."))
        ])

        #expect(mobility.executionBoundary == .mobilityOnly)
        #expect(instruction.executionBoundary == .instructionOnly)
        #expect(mobility.executionBoundary.canStartCombinedRunner)
        #expect(!instruction.executionBoundary.canStartCombinedRunner)
        #expect(!mobility.executionBoundary.canProjectToWatch)
        #expect(!instruction.executionBoundary.canProjectToWatch)
    }

    @Test func cardioMobilitySessionUsesCombinedRunnerBoundary() {
        let session = Session(title: "Run and recover", items: [
            .cardio(CardioItem(order: 0, prescription: .steadyState(SteadyState(
                activity: .run, durationSeconds: 1_800)))),
            .mobility(MobilityItem(order: 1, name: "Hip opener", perRound: .duration(seconds: 30)))
        ])

        #expect(session.executionBoundary ==
                       .mixed([.cardio, .mobility]))
        #expect(session.executionBoundary.canStartCombinedRunner)
        #expect(!session.executionBoundary.canStartStrengthRunner)
        #expect(!session.executionBoundary.canProjectToWatch)
    }

    @Test func mixedSessionCannotBeMisclassifiedAsStrengthOrWatchExecutable() {
        let session = Session(title: "Lift and run", items: [
            .strength(strengthItem()),
            .cardio(cardioItem()),
            .instruction(InstructionItem(order: 2, text: "Cool down."))
        ])

        #expect(session.executionBoundary ==
                       .mixed([.strength, .cardio, .instruction]))
        #expect(!session.executionBoundary.canStartStrengthRunner)
        #expect(!session.executionBoundary.canProjectToWatch)
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
