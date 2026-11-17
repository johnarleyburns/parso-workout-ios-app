import XCTest
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

final class SuggestionGenerationGateTests: XCTestCase {
    func testNewGenerationRejectsThePreviousResult() {
        var gate = SuggestionGenerationGate()
        let first = gate.begin()
        let second = gate.begin()

        XCTAssertFalse(gate.accepts(first))
        XCTAssertTrue(gate.accepts(second))
    }

    func testInvalidationRejectsACompletedSnapshot() {
        var gate = SuggestionGenerationGate()
        let generation = gate.begin()

        gate.invalidate()

        XCTAssertFalse(gate.accepts(generation))
    }
}
