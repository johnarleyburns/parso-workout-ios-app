import Testing
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct SuggestionGenerationGateTests {
    @Test func newGenerationRejectsThePreviousResult() {
        var gate = SuggestionGenerationGate()
        let first = gate.begin()
        let second = gate.begin()

        #expect(!gate.accepts(first))
        #expect(gate.accepts(second))
    }

    @Test func invalidationRejectsACompletedSnapshot() {
        var gate = SuggestionGenerationGate()
        let generation = gate.begin()

        gate.invalidate()

        #expect(!gate.accepts(generation))
    }
}
