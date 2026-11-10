import XCTest
@testable import CadenceCore
import CadenceFeatures

final class SuggestedStrengthPreviewTests: XCTestCase {
    private typealias F = CoachSuggestionFixtures

    private func plan(_ names: [String], title: String = "Suggested") -> EditablePlan {
        EditablePlan(title: title, warmupMinutes: 5, cooldownMinutes: 5,
                     exercises: names.map { EditableExercise(name: $0, sets: [EditableSet(targetReps: 8, targetWeight: nil)], notes: "") })
    }

    func testActionsAreExposedInRequiredOrder() {
        let c = SuggestedStrengthActionContract.ordered
        XCTAssertEqual(c.map(\.title), ["Start this Workout", "Schedule this Workout", "Suggest another", "Cancel"])
        XCTAssertEqual(c.map(\.action), [.start, .schedule, .suggestAnother, .cancel])
    }

    func testAccessibilityIdentifiersAreStable() {
        XCTAssertEqual(SuggestedStrengthActionContract.ordered.map(\.accessibilityIdentifier),
                       ["suggestedStrength.start", "suggestedStrength.schedule",
                        "suggestedStrength.another", "suggestedStrength.cancel"])
    }

    func testCancelAndInteractiveDismissClearAndOnlyCancel() {
        for action in [SuggestedStrengthAction.cancel, .interactiveDismiss] {
            var s = SuggestedStrengthPreviewState(plan: plan(["Bench Press"]))
            XCTAssertEqual(s.reduce(action), .cancelPresentation)
            XCTAssertNil(s.plan)
            XCTAssertFalse(s.isRegenerating)
            XCTAssertFalse(s.isSchedulePresented)
        }
    }

    func testStartEmitsDismissThenStartOnce() {
        let p = plan(["Bench Press"])
        var s = SuggestedStrengthPreviewState(plan: p)
        XCTAssertEqual(s.reduce(.start), .dismissThenStart(p))
        XCTAssertEqual(s.reduce(.start), .none)
        XCTAssertNil(s.plan)
    }

    func testStartUsesEditedPlan() {
        var s = SuggestedStrengthPreviewState(plan: plan(["Bench Press"]))
        let edited = plan(["Bench Press", "Barbell Row"], title: "Edited")
        s.editedPlan = edited
        XCTAssertEqual(s.reduce(.start), .dismissThenStart(edited))
    }

    func testScheduleFlow() {
        let p = plan(["Bench Press"])
        var s = SuggestedStrengthPreviewState(plan: p)
        XCTAssertEqual(s.reduce(.schedule), .none)
        XCTAssertTrue(s.isSchedulePresented)
        XCTAssertEqual(s.plan, p)
        XCTAssertEqual(s.reduce(.scheduleCancelled), .none)
        XCTAssertFalse(s.isSchedulePresented)
        XCTAssertEqual(s.plan, p)

        _ = s.reduce(.schedule)
        XCTAssertEqual(s.reduce(.scheduleSucceeded), .dismissAfterSchedule)
        XCTAssertEqual(s.reduce(.scheduleSucceeded), .none)
    }

    func testSuggestAnotherRetainsPlanAndRequestsExclusion() {
        let token = UUID()
        let p = plan(["Bench Press", "Barbell Row"])
        var s = SuggestedStrengthPreviewState(plan: p)
        let effect = s.reduce(.suggestAnother, newToken: token)
        XCTAssertEqual(effect, .requestAlternative(
            excluding: [ExerciseSuggestionExclusionKey.forName("Bench Press"),
                        ExerciseSuggestionExclusionKey.forName("Barbell Row")], token: token))
        XCTAssertTrue(s.isRegenerating)
        XCTAssertEqual(s.plan, p)
        XCTAssertEqual(s.reduce(.suggestAnother), .none, "disabled while loading")
    }

    func testReplacementSucceededReplacesAtomically() {
        let token = UUID()
        var s = SuggestedStrengthPreviewState(plan: plan(["Bench Press"]))
        _ = s.reduce(.suggestAnother, newToken: token)
        let next = plan(["Back Squat"])
        XCTAssertEqual(s.reduce(.replacementSucceeded(next, token: token)), .none)
        XCTAssertEqual(s.plan, next)
        XCTAssertEqual(s.editedPlan, next)
        XCTAssertFalse(s.isRegenerating)
    }

    func testReplacementUnavailableKeepsPlanWithMessage() {
        let token = UUID()
        let p = plan(["Bench Press"])
        var s = SuggestedStrengthPreviewState(plan: p)
        _ = s.reduce(.suggestAnother, newToken: token)
        _ = s.reduce(.replacementUnavailable(token: token))
        XCTAssertEqual(s.plan, p)
        XCTAssertFalse(s.isRegenerating)
        XCTAssertEqual(s.unavailableMessage, SuggestedStrengthPreviewState.noAlternativeMessage)
    }

    func testLateOrCancelledResultIsIgnored() {
        let token = UUID()
        let p = plan(["Bench Press"])
        var s = SuggestedStrengthPreviewState(plan: p)
        _ = s.reduce(.suggestAnother, newToken: token)
        XCTAssertEqual(s.reduce(.replacementSucceeded(plan(["X"]), token: UUID())), .none)
        XCTAssertEqual(s.plan, p)
        _ = s.reduce(.cancel)
        XCTAssertEqual(s.reduce(.replacementSucceeded(plan(["X"]), token: token)), .none)
        XCTAssertNil(s.plan)
    }

    func testOnlySuggestedStrengthGetsPreviewActions() {
        for p in [WorkoutPlanEditorPresentation.manual, .library, .previousWorkout, .scheduled] {
            XCTAssertFalse(p.showsSuggestedPreviewActions)
        }
        XCTAssertTrue(WorkoutPlanEditorPresentation.suggestedStrength.showsSuggestedPreviewActions)
    }

    func testAlternativeRequestYieldsDistinctOptionWithoutMutatingBase() throws {
        let base = F.request(candidates: F.catalog)
        let first = try XCTUnwrap(CoachSuggestionService.generate(from: F.snapshot(base)))
        let keys = Set(first.exercises.map { ExerciseSuggestionExclusionKey.forName($0.name) })
        let alt = SuggestedStrengthAlternative.request(from: base, excludingKeys: keys)
        XCTAssertEqual(base.input.candidates.count, F.catalog.count)
        let second = try XCTUnwrap(CoachSuggestionService.generate(from: F.snapshot(alt)))
        let firstIDs = Set(first.exercises.map(\.candidateID))
        XCTAssertTrue(firstIDs.isDisjoint(with: Set(second.exercises.map(\.candidateID))))
    }
}
