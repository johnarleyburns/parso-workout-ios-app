import Foundation
import Testing
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct ExerciseSelectionPolicyTests {
    @Test func browseModeNearMatchNavigatesAndDoesNotDismiss() {
        #expect(ExerciseSelectionPolicy.outcome(isBrowse: true) == .openDetail)
        #expect(ExerciseSelectionPolicy.nearMatchTitle(isBrowse: true) == "View exercise")
        #expect(!ExerciseSelectionPolicy.showsCancel(isBrowse: true))
    }

    @Test func browseModeCustomExercisePersistsThenShowsDetail() {
        #expect(ExerciseSelectionPolicy.outcome(isBrowse: true) == .openDetail)
    }

    @Test func pickerModeNearMatchCompletesAndDismisses() {
        #expect(ExerciseSelectionPolicy.outcome(isBrowse: false) == .completeAndDismiss)
        #expect(ExerciseSelectionPolicy.nearMatchTitle(isBrowse: false) == "Use this exercise")
        #expect(ExerciseSelectionPolicy.showsCancel(isBrowse: false))
    }

    @Test func pickerModeCustomExerciseCompletesAndDismisses() {
        #expect(ExerciseSelectionPolicy.outcome(isBrowse: false) == .completeAndDismiss)
    }
}

struct PlanningSelectionPolicyTests {
    @Test func planningAddsAndStaysWhilePickersDismiss() {
        #expect(ExerciseSelectionPolicy.outcome(isPlanning: true) == .addToDraftAndStay)
        #expect(ExerciseSelectionPolicy.outcome(isPlanning: false) == .completeAndDismiss)
    }

    @Test func summaryTexts() {
        #expect(PlanningDraftSummary.headline(nil) == PlanningDraftSummary.emptyMessage)
        let s = PlanningDraftSummary(id: UUID(), title: "Push", exerciseCount: 2)
        #expect(PlanningDraftSummary.headline(s) == "Push")
        #expect(PlanningDraftSummary.countText(1) == "1 exercise")
        #expect(PlanningDraftSummary.countText(2) == "2 exercises")
    }
}
