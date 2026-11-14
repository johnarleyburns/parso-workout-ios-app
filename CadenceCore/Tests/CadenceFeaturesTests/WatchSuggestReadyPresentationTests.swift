import XCTest
import CadenceCore
@testable import CadenceFeatures

final class WatchSuggestReadyPresentationTests: XCTestCase {
    func testStructuredReviewKeepsExerciseLinesAndHasNoAggregate() {
        let plan = WatchPlanPayload(strength: .init(
            exerciseNames: ["Bench Press"],
            prescriptions: [PlannedExercisePrescription(exerciseName: "Bench Press", sets: Array(
                repeating: PlannedSetPrescription(targetReps: 8), count: 3))]))
        let review = WatchSuggestReview(launch: .init(title: "Upper Body Focus", exerciseNames: ["Bench Press"],
                                                      repLadder: [8], planPayload: plan))
        XCTAssertEqual(review.title, "Upper Body Focus")
        XCTAssertEqual(review.exerciseLines, ["Bench Press · 3×8"])
        XCTAssertEqual(review.supplementalDetail, "")
        XCTAssertFalse(review.supplementalDetail.contains("working sets"))
    }

    func testFallbackReviewKeepsRepLadder() {
        let review = WatchSuggestReview(launch: .init(title: "T", exerciseNames: ["Squat"], repLadder: [5, 3, 1], planPayload: nil))
        XCTAssertEqual(review.exerciseLines, ["Squat"])
        XCTAssertEqual(review.supplementalDetail, "Reps 5-3-1")
        let empty = WatchSuggestReview(launch: .init(title: "T", exerciseNames: ["Squat"], repLadder: [], planPayload: nil))
        XCTAssertEqual(empty.supplementalDetail, "")
    }

    func testPresentationPolicy() {
        typealias P = WatchSuggestReadyPresentation
        XCTAssertEqual(P.startTitle, "Start")
        XCTAssertFalse(P.showsReadyProvenance)
        XCTAssertFalse(P.showsReadySyncTimestamp)
        XCTAssertFalse(P.showsAggregateWorkingSetCount)
        XCTAssertTrue(P.usesGreenProminentStartAction)
        XCTAssertTrue(P.showsSupplementalDetail("Reps 5-3-1"))
        XCTAssertFalse(P.showsSupplementalDetail(""))
    }

    func testActiveWorkoutGuard() {
        typealias P = WatchSuggestReadyPresentation
        XCTAssertTrue(P.isStartDisabled(workoutActive: true))
        XCTAssertEqual(P.activeWorkoutMessage(workoutActive: true), "Finish or resume your current workout first.")
        XCTAssertFalse(P.isStartDisabled(workoutActive: false))
        XCTAssertNil(P.activeWorkoutMessage(workoutActive: false))
    }
}
