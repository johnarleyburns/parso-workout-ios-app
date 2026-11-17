import XCTest
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

final class CoachWarningModalityFilterTests: XCTestCase {
    private func warning(_ id: String, _ modality: CoachWarning.Modality) -> CoachWarning {
        CoachWarning(id: id, message: id, modality: modality)
    }

    func testStrengthRequestSurfacesStrengthAndGeneralOnly() {
        let all = [warning("a", .strength), warning("b", .cardio), warning("c", .general)]
        let filtered = CoachWarningModalityFilter.filter(all, for: .strength)
        XCTAssertEqual(Set(filtered.map(\.id)), ["a", "c"])
    }

    func testCardioRequestSurfacesCardioAndGeneralOnly() {
        let all = [warning("a", .strength), warning("b", .cardio), warning("c", .general)]
        let filtered = CoachWarningModalityFilter.filter(all, for: .cardio)
        XCTAssertEqual(Set(filtered.map(\.id)), ["b", "c"])
    }

    func testOrderIsPreserved() {
        let all = [warning("a", .general), warning("b", .strength), warning("c", .general)]
        XCTAssertEqual(CoachWarningModalityFilter.filter(all, for: .strength).map(\.id), ["a", "b", "c"])
    }
}
