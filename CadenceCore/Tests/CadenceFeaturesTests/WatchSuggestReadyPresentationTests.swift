import Testing
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchSuggestReadyPresentationTests {
    @Test func structuredReviewKeepsExerciseLinesAndHasNoAggregate() {
        let plan = WatchPlanPayload(strength: .init(
            exerciseNames: ["Bench Press"],
            prescriptions: [PlannedExercisePrescription(exerciseName: "Bench Press", sets: Array(
                repeating: PlannedSetPrescription(targetReps: 8), count: 3))]))
        let review = WatchSuggestReview(launch: .init(title: "Upper Body Focus", exerciseNames: ["Bench Press"],
                                                      repLadder: [8], planPayload: plan))
        #expect(review.title == "Upper Body Focus")
        #expect(review.exerciseLines == ["Bench Press · 3×8"])
        #expect(review.supplementalDetail == "")
        #expect(!review.supplementalDetail.contains("working sets"))
    }

    @Test func fallbackReviewKeepsRepLadder() {
        let review = WatchSuggestReview(launch: .init(title: "T", exerciseNames: ["Squat"], repLadder: [5, 3, 1], planPayload: nil))
        #expect(review.exerciseLines == ["Squat"])
        #expect(review.supplementalDetail == "Reps 5-3-1")
        let empty = WatchSuggestReview(launch: .init(title: "T", exerciseNames: ["Squat"], repLadder: [], planPayload: nil))
        #expect(empty.supplementalDetail == "")
    }

    @Test func presentationPolicy() {
        typealias P = WatchSuggestReadyPresentation
        #expect(P.startTitle == "Start")
        #expect(!P.showsReadyProvenance)
        #expect(!P.showsReadySyncTimestamp)
        #expect(!P.showsAggregateWorkingSetCount)
        #expect(P.usesGreenProminentStartAction)
        #expect(P.showsSupplementalDetail("Reps 5-3-1"))
        #expect(!P.showsSupplementalDetail(""))
    }

    @Test func activeWorkoutGuard() {
        typealias P = WatchSuggestReadyPresentation
        #expect(P.isStartDisabled(workoutActive: true))
        #expect(P.activeWorkoutMessage(workoutActive: true) == "Finish or resume your current workout first.")
        #expect(!P.isStartDisabled(workoutActive: false))
        #expect(P.activeWorkoutMessage(workoutActive: false) == nil)
    }
}
