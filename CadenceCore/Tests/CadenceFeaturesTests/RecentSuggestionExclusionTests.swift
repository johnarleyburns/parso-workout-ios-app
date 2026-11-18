import Foundation
import Testing
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct RecentSuggestionExclusionTests {
    @Test func usesMostRecentCompletedWorkoutEvenWhenItIsOnAnEarlierDay() {
        let older = RecentCompletedWorkoutSnapshot(
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200),
            exerciseNames: ["Bench Press"])
        let latest = RecentCompletedWorkoutSnapshot(
            startedAt: Date(timeIntervalSince1970: 300),
            endedAt: Date(timeIntervalSince1970: 400),
            exerciseNames: ["Cable Row", "  " ] )

        #expect(
            RecentSuggestionExclusion.exerciseNames(from: [latest, older])
            == ["cable row"])
    }

    @Test func completionTimeWinsOverStartTime() {
        let startedLaterButFinishedEarlier = RecentCompletedWorkoutSnapshot(
            startedAt: Date(timeIntervalSince1970: 300),
            endedAt: Date(timeIntervalSince1970: 350),
            exerciseNames: ["Bench Press"])
        let startedEarlierButFinishedLater = RecentCompletedWorkoutSnapshot(
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 400),
            exerciseNames: ["Deadlift"])

        #expect(
            RecentSuggestionExclusion.exerciseNames(
                from: [startedLaterButFinishedEarlier, startedEarlierButFinishedLater])
            == ["deadlift"])
    }
}
