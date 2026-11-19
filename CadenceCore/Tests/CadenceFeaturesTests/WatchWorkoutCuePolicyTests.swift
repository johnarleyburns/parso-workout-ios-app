import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchWorkoutCuePolicyTests {
    @Test func strengthRestCompletionPlaysExactlyThreeDistinctBells() {
        #expect(WatchWorkoutCuePolicy.restCompletionBellOffsets.count == 3)
        #expect(WatchWorkoutCuePolicy.restCompletionBellOffsets == [0, 0.85, 1.70])
    }
}
