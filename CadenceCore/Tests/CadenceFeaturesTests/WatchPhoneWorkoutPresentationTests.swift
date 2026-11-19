import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchPhoneWorkoutPresentationTests {
    @Test func phoneWorkoutScreenShowsOnlyForActivePhoneOwnedWorkout() {
        #expect(WatchPhoneWorkoutPresentation.shouldShow(isActive: true, phoneRequestID: "request"))
        #expect(!WatchPhoneWorkoutPresentation.shouldShow(isActive: false, phoneRequestID: "request"))
        #expect(!WatchPhoneWorkoutPresentation.shouldShow(isActive: true, phoneRequestID: nil))
    }
}
