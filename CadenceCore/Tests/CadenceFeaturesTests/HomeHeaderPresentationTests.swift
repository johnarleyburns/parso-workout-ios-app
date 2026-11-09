import XCTest
import CadenceFeatures

final class HomeHeaderPresentationTests: XCTestCase {
    func testSupporterProducesAchievementBadge() throws {
        let badge = try XCTUnwrap(HomeHeaderPresentation(isSupporter: true).supporterBadge)
        XCTAssertEqual(badge.text, "Supporter")
        XCTAssertEqual(badge.accessibilityLabel, "Supporter")
        XCTAssertEqual(badge.systemImage, "heart.fill")
        XCTAssertEqual(badge.tint, .achievement)
        XCTAssertEqual(badge.accessibilityIdentifier, "home.supporterBadge")
    }

    func testNonSupporterHasNoBadge() {
        XCTAssertNil(HomeHeaderPresentation(isSupporter: false).supporterBadge)
    }
}
