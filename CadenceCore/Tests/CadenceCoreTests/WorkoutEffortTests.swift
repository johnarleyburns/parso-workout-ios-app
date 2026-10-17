import Testing
@testable import CadenceCore

@Suite struct WorkoutEffortTests {
    @Test func strengthAveragesRPEAndIgnoresMissing() {
        #expect(WorkoutEffort.strengthScore(workingSetRPEs: []) == nil)
        #expect(WorkoutEffort.strengthScore(workingSetRPEs: [7, 9]) == 8)
        #expect(WorkoutEffort.strengthScore(workingSetRPEs: [12]) == 10)
    }

    @Test func cardioNeedsClassifiedTime() {
        #expect(WorkoutEffort.cardioScore(nil) == nil)
    }
}
