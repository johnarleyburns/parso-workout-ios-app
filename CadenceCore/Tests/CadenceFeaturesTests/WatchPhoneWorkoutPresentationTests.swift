import XCTest
@testable import CadenceFeatures

final class WatchPhoneWorkoutPresentationTests: XCTestCase {
    func testPhoneWorkoutScreenShowsOnlyForActivePhoneOwnedWorkout() {
        XCTAssertTrue(WatchPhoneWorkoutPresentation.shouldShow(isActive: true, phoneRequestID: "request"))
        XCTAssertFalse(WatchPhoneWorkoutPresentation.shouldShow(isActive: false, phoneRequestID: "request"))
        XCTAssertFalse(WatchPhoneWorkoutPresentation.shouldShow(isActive: true, phoneRequestID: nil))
    }
}
