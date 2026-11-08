import XCTest
import CadenceCore
@testable import CadenceFeatures

final class TodaySuggestionReplacementGateTests: XCTestCase {
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

    func testNothingDisplayedAppliesImmediately() {
        XCTAssertEqual(TodaySuggestionReplacementGate.decide(displayed: nil, freshlyComputed: payload()),
                       .applyImmediately)
    }

    func testIdenticalRecomputeAppliesImmediately() {
        XCTAssertEqual(TodaySuggestionReplacementGate.decide(displayed: payload(), freshlyComputed: payload()),
                       .applyImmediately)
    }

    func testDifferentTitleHoldsPending() {
        XCTAssertEqual(TodaySuggestionReplacementGate.decide(displayed: payload(title: "Push"),
                                                             freshlyComputed: payload(title: "Pull")),
                       .holdPending)
    }

    func testDifferentExercisesHoldsPending() {
        XCTAssertEqual(TodaySuggestionReplacementGate.decide(displayed: payload(exercise: "Bench Press"),
                                                             freshlyComputed: payload(exercise: "Squat")),
                       .holdPending)
    }
}
