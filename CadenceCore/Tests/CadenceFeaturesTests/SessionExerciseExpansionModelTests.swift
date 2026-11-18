import Foundation
import Testing
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct SessionExerciseExpansionModelTests {
    @Test func initialAndToggle() {
        let a = UUID(), b = UUID()
        #expect(SessionExerciseExpansionModel.initial(exerciseIDs: [a, b], unfinishedIDs: [b], mode: .active) == b)
        #expect(SessionExerciseExpansionModel.initial(exerciseIDs: [a], unfinishedIDs: [], mode: .active) == nil)
        #expect(SessionExerciseExpansionModel.initial(exerciseIDs: [a], unfinishedIDs: [a], mode: .review) == nil)
        #expect(SessionExerciseExpansionModel.headerTapped(current: a, tapped: a) == nil)
        #expect(SessionExerciseExpansionModel.headerTapped(current: a, tapped: b) == b)
    }

    @Test func saveTransitions() {
        let a = UUID(), b = UUID()
        #expect(SessionExerciseExpansionModel.afterSave(current: a, savedExerciseID: a, nextUnfinishedID: b, kind: .pending) == a)
        #expect(SessionExerciseExpansionModel.afterSave(current: a, savedExerciseID: a, nextUnfinishedID: b, kind: .unplanned) == a)
        #expect(SessionExerciseExpansionModel.afterSave(current: a, savedExerciseID: a, nextUnfinishedID: b, kind: .finalPlanned) == b)
    }
}
