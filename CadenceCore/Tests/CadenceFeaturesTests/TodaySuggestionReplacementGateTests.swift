import Foundation
import Testing
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct TodaySuggestionReplacementGateTests {
    private func payload(title: String = "Push", exercise: String = "Bench Press") -> TodaySuggestedPlanPayload {
        TodaySuggestedPlanPayload(EditablePlan(
            title: title, warmupMinutes: 5, cooldownMinutes: 3,
            exercises: [EditableExercise(
                name: exercise,
                sets: [EditableSet(targetReps: 8, targetWeight: 60,
                                   loadMode: .percentageOfOneRepMax, oneRepMaxPercent: 0.7)],
                notes: "")],
            enginePlanId: "plan", engineRevisionId: "rev", enginePlanJSON: Data([1])))
    }

    @Test func nothingDisplayedAppliesImmediately() {
        #expect(TodaySuggestionReplacementGate.decide(displayed: nil, freshlyComputed: payload()) ==
                       .applyImmediately)
    }

    @Test func identicalRecomputeAppliesImmediately() {
        #expect(TodaySuggestionReplacementGate.decide(displayed: payload(), freshlyComputed: payload()) ==
                       .applyImmediately)
    }

    @Test func differentTitleHoldsPending() {
        #expect(TodaySuggestionReplacementGate.decide(displayed: payload(title: "Push"),
                                                             freshlyComputed: payload(title: "Pull")) ==
                       .holdPending)
    }

    @Test func differentExercisesHoldsPending() {
        #expect(TodaySuggestionReplacementGate.decide(displayed: payload(exercise: "Bench Press"),
                                                             freshlyComputed: payload(exercise: "Squat")) ==
                       .holdPending)
    }
}
