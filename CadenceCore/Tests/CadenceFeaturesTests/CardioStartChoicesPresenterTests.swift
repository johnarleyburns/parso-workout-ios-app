import XCTest
import CadenceCore
@testable import CadenceFeatures

final class CardioStartChoicesPresenterTests: XCTestCase {
    private let all: [WorkoutType] = [.run, .walk, .cycle, .rowing, .swim,
                                      .elliptical, .stairClimber, .hiit, .boxing]

    func testEmptyHistoryUsesRunCycleSwim() {
        XCTAssertEqual(CardioStartChoicesPresenter.initial(recent: [], all: all),
                       [.run, .cycle, .swim])
    }

    func testOneRecentTypeFillsRemainingSlotsWithoutDuplicates() {
        XCTAssertEqual(CardioStartChoicesPresenter.initial(recent: [.rowing], all: all),
                       [.rowing, .run, .cycle])
    }

    func testRecentOrderWinsAndDuplicatesAreRemoved() {
        XCTAssertEqual(CardioStartChoicesPresenter.initial(
            recent: [.run, .run, .swim, .cycle], all: all),
            [.run, .swim, .cycle])
    }

    func testRemainingContainsOnlyUnshownCardioTypes() {
        let initial = CardioStartChoicesPresenter.initial(recent: [.rowing], all: all)
        XCTAssertEqual(CardioStartChoicesPresenter.remaining(initial: initial, all: all),
                       [.walk, .swim, .elliptical, .stairClimber, .hiit, .boxing])
    }
}
