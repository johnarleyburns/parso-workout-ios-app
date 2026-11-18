import Foundation
import Testing
@testable import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct SuggestedStrengthPreviewTests {
    private typealias F = CoachSuggestionFixtures

    private func plan(_ names: [String], title: String = "Suggested") -> EditablePlan {
        EditablePlan(title: title, warmupMinutes: 5, cooldownMinutes: 5,
                     exercises: names.map { EditableExercise(name: $0, sets: [EditableSet(targetReps: 8, targetWeight: nil)], notes: "") })
    }

    @Test func actionsAreExposedInRequiredOrder() {
        let c = SuggestedStrengthActionContract.ordered
        #expect(c.map(\.title) == ["Start this Workout", "Suggest another", "Cancel"])
        #expect(c.map(\.action) == [.start, .suggestAnother, .cancel])
    }

    @Test func accessibilityIdentifiersAreStable() {
        #expect(SuggestedStrengthActionContract.ordered.map(\.accessibilityIdentifier) ==
                       ["suggestedStrength.start",
                        "suggestedStrength.another", "suggestedStrength.cancel"])
    }

    @Test func cancelAndInteractiveDismissClearAndOnlyCancel() {
        for action in [SuggestedStrengthAction.cancel, .interactiveDismiss] {
            var s = SuggestedStrengthPreviewState(plan: plan(["Bench Press"]))
            #expect(s.reduce(action) == .cancelPresentation)
            #expect(s.plan == nil)
            #expect(!s.isRegenerating)
        }
    }

    @Test func startEmitsDismissThenStartOnce() {
        let p = plan(["Bench Press"])
        var s = SuggestedStrengthPreviewState(plan: p)
        #expect(s.reduce(.start) == .dismissThenStart(p))
        #expect(s.reduce(.start) == .none)
        #expect(s.plan == nil)
    }

    @Test func startUsesEditedPlan() {
        var s = SuggestedStrengthPreviewState(plan: plan(["Bench Press"]))
        let edited = plan(["Bench Press", "Barbell Row"], title: "Edited")
        s.editedPlan = edited
        #expect(s.reduce(.start) == .dismissThenStart(edited))
    }


    @Test func suggestAnotherRetainsPlanAndRequestsExclusion() {
        let token = UUID()
        let p = plan(["Bench Press", "Barbell Row"])
        var s = SuggestedStrengthPreviewState(plan: p)
        let effect = s.reduce(.suggestAnother, newToken: token)
        #expect(effect == .requestAlternative(
            excluding: [ExerciseSuggestionExclusionKey.forName("Bench Press"),
                        ExerciseSuggestionExclusionKey.forName("Barbell Row")], token: token))
        #expect(s.isRegenerating)
        #expect(s.plan == p)
        #expect(s.reduce(.suggestAnother) == .none, "disabled while loading")
    }

    @Test func replacementSucceededReplacesAtomically() {
        let token = UUID()
        var s = SuggestedStrengthPreviewState(plan: plan(["Bench Press"]))
        _ = s.reduce(.suggestAnother, newToken: token)
        let next = plan(["Back Squat"])
        #expect(s.reduce(.replacementSucceeded(next, token: token)) == .none)
        #expect(s.plan == next)
        #expect(s.editedPlan == next)
        #expect(!s.isRegenerating)
    }

    @Test func replacementUnavailableKeepsPlanWithMessage() {
        let token = UUID()
        let p = plan(["Bench Press"])
        var s = SuggestedStrengthPreviewState(plan: p)
        _ = s.reduce(.suggestAnother, newToken: token)
        _ = s.reduce(.replacementUnavailable(token: token))
        #expect(s.plan == p)
        #expect(!s.isRegenerating)
        #expect(s.unavailableMessage == SuggestedStrengthPreviewState.noAlternativeMessage)
    }

    @Test func lateOrCancelledResultIsIgnored() {
        let token = UUID()
        let p = plan(["Bench Press"])
        var s = SuggestedStrengthPreviewState(plan: p)
        _ = s.reduce(.suggestAnother, newToken: token)
        #expect(s.reduce(.replacementSucceeded(plan(["X"]), token: UUID())) == .none)
        #expect(s.plan == p)
        _ = s.reduce(.cancel)
        #expect(s.reduce(.replacementSucceeded(plan(["X"]), token: token)) == .none)
        #expect(s.plan == nil)
    }

    @Test func onlySuggestedStrengthGetsPreviewActions() {
        for p in [WorkoutPlanEditorPresentation.manual, .library, .previousWorkout] {
            #expect(!p.showsSuggestedPreviewActions)
        }
        #expect(WorkoutPlanEditorPresentation.suggestedStrength.showsSuggestedPreviewActions)
    }

    @Test func alternativeRequestYieldsDistinctOptionWithoutMutatingBase() throws {
        let base = F.request(candidates: F.catalog)
        let first = try #require(CoachSuggestionService.generate(from: F.snapshot(base)))
        let keys = Set(first.exercises.map { ExerciseSuggestionExclusionKey.forName($0.name) })
        let alt = SuggestedStrengthAlternative.request(from: base, excludingKeys: keys)
        #expect(base.input.candidates.count == F.catalog.count)
        let second = try #require(CoachSuggestionService.generate(from: F.snapshot(alt)))
        let firstIDs = Set(first.exercises.map(\.candidateID))
        #expect(firstIDs.isDisjoint(with: Set(second.exercises.map(\.candidateID))))
    }
}
