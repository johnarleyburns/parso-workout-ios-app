import Testing
import CadenceFeatures
import CadenceWorkoutFeatures

/// Deliberately no @testable: the Watch app consumes this public initializer.
struct WatchLiftLaunchPublicAPITests {
    @Test func watchAppCanConstructFreshSuggestionLaunch() {
        let launch = WatchLiftLaunch(title: "Suggested", exerciseNames: ["Biceps Curl"], repLadder: [10])
        #expect(launch.title == "Suggested")
        #expect(launch.exerciseNames == ["Biceps Curl"])
        #expect(launch.repLadder == [10])
        #expect(launch.planPayload == nil)
    }
}
