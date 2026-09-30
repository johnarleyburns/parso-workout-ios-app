import XCTest
@testable import CadenceFeatures

final class RecentSuggestionExclusionTests: XCTestCase {
    func testUsesMostRecentCompletedWorkoutEvenWhenItIsOnAnEarlierDay() {
        let older = RecentCompletedWorkoutSnapshot(
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            exerciseNames: ["Bench Press"])
        let latest = RecentCompletedWorkoutSnapshot(
            startedAt: Date(timeIntervalSince1970: 300),
            endedAt: Date(timeIntervalSince1970: 400),
            exerciseNames: ["Cable Row", "  " ] )

        XCTAssertEqual(
            RecentSuggestionExclusion.exerciseNames(from: [latest, older]),
            ["cable row"])
    }

    func testCompletionTimeWinsOverStartTime() {
        let startedLaterButFinishedEarlier = RecentCompletedWorkoutSnapshot(
            startedAt: Date(timeIntervalSince1970: 300),
            endedAt: Date(timeIntervalSince1970: 350),
            exerciseNames: ["Bench Press"])
        let startedEarlierButFinishedLater = RecentCompletedWorkoutSnapshot(
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 400),
            exerciseNames: ["Deadlift"])

        XCTAssertEqual(
            RecentSuggestionExclusion.exerciseNames(
                from: [startedLaterButFinishedEarlier, startedEarlierButFinishedLater]),
            ["deadlift"])
    }
}
