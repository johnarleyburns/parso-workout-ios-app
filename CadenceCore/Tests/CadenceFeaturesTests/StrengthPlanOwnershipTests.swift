import XCTest
@testable import CadenceFeatures

final class StrengthPlanOwnershipTests: XCTestCase {
    func testOnlyManualFindDraftIsDurable() {
        XCTAssertEqual(StrengthPlanPolicy.persistence(for: .manualFindDraft), .durablePlanningDraft)
        for origin in [StrengthPlanOrigin.muscleCoverageSuggestion, .personalizedSuggestion, .library, .scheduled] {
            XCTAssertEqual(StrengthPlanPolicy.persistence(for: origin), .transientEditor)
        }
    }

    func testDraftSectionEmptyWhenNoDraft() {
        XCTAssertEqual(StrengthDraftSectionPresenter.state(for: nil), .empty)
        XCTAssertEqual(StrengthDraftSectionPresenter.state(for: PlanningDraftSummary(id: UUID(), title: "X", exerciseCount: 0)), .empty)
    }

    func testDraftSectionSummary() {
        let id = UUID()
        let state = StrengthDraftSectionPresenter.state(for: PlanningDraftSummary(id: id, title: "Push", exerciseCount: 3))
        XCTAssertEqual(state, .summary(title: "Push", exerciseCount: 3))
        XCTAssertEqual(StrengthDraftSectionPresenter.sectionIdentifier, "weights.draftWorkout")
        XCTAssertEqual(StrengthDraftSectionPresenter.emptyIdentifier, "weights.draftWorkout.empty")
        XCTAssertEqual(StrengthDraftSectionPresenter.continueIdentifier, "weights.draftWorkout.continue")
    }

    func testDraftIsFinalStrengthSectionOnceAndNotGlobal() {
        let s = StrengthScreenLayout.sections
        XCTAssertEqual(s.last, .draftWorkout)
        XCTAssertEqual(s.filter { $0 == .draftWorkout }.count, 1)
        XCTAssertEqual(s.dropLast().last, .hrMonitoring)
        XCTAssertFalse(RootDraftPresentationPolicy.showsGlobalDraftStrip)
        XCTAssertFalse(RootDraftPresentationPolicy.showsGlobalDraftSheet)
    }

    func testSuggestionScreenLayout() {
        XCTAssertEqual(MuscleCoverageSuggestionLayout.title, "Strength Workout")
        let rows = MuscleCoverageSuggestionLayout.sections
        XCTAssertEqual(rows, [.suggestedExercises])
    }

    func testTransientEditorContentOrder() {
        XCTAssertEqual(TransientStrengthEditorContent.order, [
            .startWorkout, .sendToWatch, .scheduleThisWorkout,
            .exerciseRows, .addExercise, .suggestExercise,
            .trainingPartners, .volumeSummary])
        XCTAssertEqual(TransientStrengthEditorContent.order.last, .volumeSummary)
    }
}
