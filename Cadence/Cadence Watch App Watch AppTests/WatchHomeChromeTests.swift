import Testing
import HealthKit
@testable import Cadence_Watch_App_Watch_App

struct WatchHomeChromeTests {
    @Test("The launcher uses its product name as the native navigation title")
    func launcherNavigationTitleIsCladiron() {
        #expect(WatchHomeChrome.navigationTitle == "Cladiron")
    }
    @Test("The full home catalog records and recovers elliptical and stair workouts correctly")
    @MainActor
    func extendedCardioTypesPreserveHealthKitIdentity() {
        #expect(WatchWorkoutManager.activityType(for: "elliptical") == .elliptical)
        #expect(WatchWorkoutManager.activityType(for: "stairClimber") == .stairClimbing)
        #expect(WatchWorkoutManager.rawType(for: .elliptical) == "elliptical")
        #expect(WatchWorkoutManager.rawType(for: .stairClimbing) == "stairClimber")
    }

}
