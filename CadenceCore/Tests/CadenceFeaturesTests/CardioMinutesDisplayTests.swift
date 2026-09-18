import XCTest
@testable import CadenceFeatures

final class CardioMinutesDisplayTests: XCTestCase {
    func testLoggedMinutesFormatsZeroFractionalAndNonZeroValues() {
        XCTAssertEqual(CardioMinutesDisplay.logged(0), "0 min")
        XCTAssertEqual(CardioMinutesDisplay.logged(12.4), "12 min")
        XCTAssertEqual(CardioMinutesDisplay.logged(12.5), "13 min")
    }

    func testModerateEquivalentFormatsActualAndTarget() {
        XCTAssertEqual(CardioMinutesDisplay.moderateEquivalent(0, target: 150), "0 of 150 min")
        XCTAssertEqual(CardioMinutesDisplay.moderateEquivalent(157.6, target: 150), "158 of 150 min")
    }

    func testUnclassifiedAndZoneValuesNeverExposeSourceExpressions() {
        let values = [
            CardioMinutesDisplay.unclassified(4.2),
            CardioMinutesDisplay.zone(7.8)
        ]
        XCTAssertEqual(values, ["4 min could not be intensity-classified", "8 min"])
        XCTAssertFalse(values.joined(separator: " ").contains("dashboard.cardioDetail"))
        XCTAssertFalse(values.joined(separator: " ").contains("Int("))
    }
}
