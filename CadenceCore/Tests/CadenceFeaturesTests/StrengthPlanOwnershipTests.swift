import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct StrengthPlanOwnershipTests {
    @Test func onlyManualFindDraftIsDurable() {
        #expect(StrengthPlanPolicy.persistence(for: .manualFindDraft) == .durablePlanningDraft)
        for origin in [StrengthPlanOrigin.muscleCoverageSuggestion, .personalizedSuggestion, .library, .scheduled] {
            #expect(StrengthPlanPolicy.persistence(for: origin) == .transientEditor)
        }
    }

    @Test func draftSectionEmptyWhenNoDraft() {
        #expect(StrengthDraftSectionPresenter.state(for: nil) == .empty)
        #expect(StrengthDraftSectionPresenter.state(for: PlanningDraftSummary(id: UUID(), title: "X", exerciseCount: 0)) == .empty)
    }

    @Test func draftSectionSummary() {
        let id = UUID()
        let state = StrengthDraftSectionPresenter.state(for: PlanningDraftSummary(id: id, title: "Push", exerciseCount: 3))
        #expect(state == .summary(title: "Push", exerciseCount: 3))
        #expect(StrengthDraftSectionPresenter.sectionIdentifier == "weights.draftWorkout")
        #expect(StrengthDraftSectionPresenter.emptyIdentifier == "weights.draftWorkout.empty")
        #expect(StrengthDraftSectionPresenter.continueIdentifier == "weights.draftWorkout.continue")
    }

    @Test func draftIsFinalStrengthSectionOnceAndNotGlobal() {
        let s = StrengthScreenLayout.sections
        #expect(s.last == .draftWorkout)
        #expect(s.filter { $0 == .draftWorkout }.count == 1)
        #expect(s.dropLast().last == .hrMonitoring)
        #expect(!RootDraftPresentationPolicy.showsGlobalDraftStrip)
        #expect(!RootDraftPresentationPolicy.showsGlobalDraftSheet)
    }

    @Test func suggestionScreenLayout() {
        #expect(MuscleCoverageSuggestionLayout.title == "Strength Workout")
        let rows = MuscleCoverageSuggestionLayout.sections
        #expect(rows == [.suggestedExercises])
    }

    @Test func transientEditorContentOrder() {
        #expect(TransientStrengthEditorContent.order == [
            .startWorkout, .sendToWatch, .scheduleThisWorkout,
            .exerciseRows, .addExercise, .suggestExercise,
            .trainingPartners, .volumeSummary])
        #expect(TransientStrengthEditorContent.order.last == .volumeSummary)
    }
}
