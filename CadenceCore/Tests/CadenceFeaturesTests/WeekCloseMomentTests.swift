import XCTest
@testable import CadenceFeatures

final class WeekCloseMomentTests: XCTestCase {
    func testWeekCloseRequiresAllThreeGoals() {
        XCTAssertNil(WeekCloseMoment.make(workingSets: 12, setTarget: 12,
                                          cardioMinutes: 20, cardioTarget: 30,
                                          sessions: 3, sessionTarget: 3))
        XCTAssertEqual(WeekCloseMoment.make(workingSets: 12, setTarget: 12,
                                            cardioMinutes: 30, cardioTarget: 30,
                                            sessions: 3, sessionTarget: 3)?.title, "Week complete")
    }
}
