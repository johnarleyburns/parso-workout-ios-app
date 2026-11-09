import XCTest
@testable import CadenceFeatures

final class SupportDevelopmentCardStateTests: XCTestCase {
    func testAvailableProductIsPurchaseable() {
        let s = SupportDevelopmentCardState.make(productPrice: "$9.99", isSupporter: false, purchasingID: nil)
        XCTAssertEqual(s.kind, .purchaseable)
        XCTAssertEqual(s.priceText, "$9.99")
        XCTAssertTrue(s.canPurchase)
        XCTAssertTrue(s.isEnabled)
        XCTAssertEqual(s.iconName, "heart.fill")
    }

    func testUnavailableProductIsDisabledWithNoPurchase() {
        let s = SupportDevelopmentCardState.make(productPrice: nil, isSupporter: false, purchasingID: nil)
        XCTAssertEqual(s.kind, .unavailable)
        XCTAssertFalse(s.isEnabled)
        XCTAssertFalse(s.canPurchase)
    }

    func testPurchasingIsDisabledLoading() {
        let s = SupportDevelopmentCardState.make(productPrice: "$9.99", isSupporter: false, purchasingID: "x")
        XCTAssertEqual(s.kind, .purchasing)
        XCTAssertFalse(s.isEnabled)
        XCTAssertTrue(s.showsProgress)
    }

    func testSupporterShowsThanks() {
        let s = SupportDevelopmentCardState.make(productPrice: "$9.99", isSupporter: true, purchasingID: nil)
        XCTAssertEqual(s.kind, .supporter)
        XCTAssertFalse(s.canPurchase)
    }

    func testSupportSectionPrecedesHealth() throws {
        let ids = SettingsSectionOrder.identifiers
        XCTAssertEqual(ids.first, "settings.section.support")
        XCTAssertLessThan(try XCTUnwrap(ids.firstIndex(of: "settings.section.support")),
                          try XCTUnwrap(ids.firstIndex(of: "settings.section.health")))
    }
}
