import Testing
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct CoachWarningModalityFilterTests {
    private func warning(_ id: String, _ modality: CoachWarning.Modality) -> CoachWarning {
        CoachWarning(id: id, message: id, modality: modality)
    }

    @Test func strengthRequestSurfacesStrengthAndGeneralOnly() {
        let all = [warning("a", .strength), warning("b", .cardio), warning("c", .general)]
        let filtered = CoachWarningModalityFilter.filter(all, for: .strength)
        #expect(Set(filtered.map(\.id)) == ["a", "c"])
    }

    @Test func cardioRequestSurfacesCardioAndGeneralOnly() {
        let all = [warning("a", .strength), warning("b", .cardio), warning("c", .general)]
        let filtered = CoachWarningModalityFilter.filter(all, for: .cardio)
        #expect(Set(filtered.map(\.id)) == ["b", "c"])
    }

    @Test func orderIsPreserved() {
        let all = [warning("a", .general), warning("b", .strength), warning("c", .general)]
        #expect(CoachWarningModalityFilter.filter(all, for: .strength).map(\.id) == ["a", "b", "c"])
    }
}
