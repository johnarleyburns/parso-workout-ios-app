import XCTest
@testable import CadenceFeatures

final class ThisWeekWorkoutsPresenterTests: XCTestCase {
    func testSummaryVariants() {
        XCTAssertEqual(ThisWeekWorkoutsPresenter.summary(planned: 3, done: 2), "3 workouts planned, 2 workouts done")
        XCTAssertEqual(ThisWeekWorkoutsPresenter.summary(planned: 3, done: 0), "3 workouts planned")
        XCTAssertEqual(ThisWeekWorkoutsPresenter.summary(planned: 0, done: 2), "2 workouts done")
        XCTAssertEqual(ThisWeekWorkoutsPresenter.summary(planned: 0, done: 0), "No workouts planned or done")
    }
}
