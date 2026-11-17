import XCTest
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

final class WeekCloseMomentTests: XCTestCase {
    func testWeekCloseRequiresBothGoals() {
        XCTAssertNil(WeekCloseMoment.make(workingSets: 12, setTarget: 12,
                                          cardioMinutes: 20, cardioTarget: 30))
        XCTAssertEqual(WeekCloseMoment.make(workingSets: 12, setTarget: 12,
                                            cardioMinutes: 30, cardioTarget: 30)?.title, "Week complete")
    }
}
