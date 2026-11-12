import XCTest
import CadenceFeatures

final class SupporterSurfacePresentationTests: XCTestCase {
    func testTrailingItemsOnlyIncludeBadgeBeforeSettingsForSupporter() {
        XCTAssertEqual(HomeHeaderPresentation(isSupporter: false).trailingItems, [.settings])
        XCTAssertEqual(HomeHeaderPresentation(isSupporter: true).trailingItems, [.supporterBadge, .settings])
    }

    func testBadgeMetrics() throws {
        let badge = try XCTUnwrap(HomeHeaderPresentation(isSupporter: true).supporterBadge)
        XCTAssertEqual(badge.horizontalPadding, 10)
        XCTAssertEqual(badge.verticalPadding, 6)
    }

    func testSettingsHasSingleCardSupportGroupFirst() {
        XCTAssertEqual(SettingsSectionOrder.identifiers.filter { $0 == "settings.section.support" }.count, 1)
        XCTAssertEqual(SettingsSectionOrder.identifiers.first, "settings.section.support")
        XCTAssertEqual(SettingsSectionOrder.supportCardCount, 1)
    }

    func testCardCopy() {
        let a = SupporterSurfacePresentation(isSupporter: false, result: .idle, productName: "App")
        XCTAssertEqual(a.settingsTitle, "Contribute to Development")
        XCTAssertEqual(a.settingsDetail, "A one-time, optional $9.99 — every feature is already free")
        XCTAssertFalse(a.showsTodayBadge)
        let b = SupporterSurfacePresentation(isSupporter: true, result: .idle, productName: "App")
        XCTAssertEqual(b.settingsTitle, "Thanks for supporting App")
        XCTAssertEqual(b.settingsDetail, "You have the Supporter badge")
        XCTAssertTrue(b.showsTodayBadge)
    }

    func testReducerPreventsDuplicatesAndRestores() {
        var s = SupporterPurchaseState()
        XCTAssertTrue(SupporterSurfacePresentation(isSupporter: false, result: s.result, productName: "A").isPurchaseEnabled)
        XCTAssertTrue(s.begin())
        XCTAssertFalse(s.begin())
        XCTAssertFalse(SupporterSurfacePresentation(isSupporter: false, result: s.result, productName: "A").isPurchaseEnabled)
        s.finish(.cancelledOrPending)
        XCTAssertEqual(s.result, .idle)
        XCTAssertTrue(s.begin())
    }

    func testSuccessAndFailureResults() {
        var s = SupporterPurchaseState()
        _ = s.begin(); s.finish(.verifiedSuccess)
        let ok = SupporterSurfacePresentation(isSupporter: true, result: s.result, productName: "App")
        XCTAssertEqual(ok.resultMessage, "Thank you for supporting App!")
        XCTAssertTrue(ok.showsTodayBadge)
        _ = s.begin(); s.finish(.failure(message: "boom"))
        let bad = SupporterSurfacePresentation(isSupporter: false, result: s.result, productName: "App")
        XCTAssertEqual(bad.resultMessage, "Purchase failed: boom")
        XCTAssertFalse(bad.showsTodayBadge)
        XCTAssertTrue(bad.isPurchaseEnabled)
    }

    func testCancelKeepsPriorSuccessMessage() {
        var s = SupporterPurchaseState()
        _ = s.begin(); s.finish(.verifiedSuccess)
        _ = s.begin(); s.finish(.cancelledOrPending)
        XCTAssertEqual(s.result, .succeeded)
    }

    func testBothSurfacesObserveSameFlag() {
        for flag in [false, true] {
            XCTAssertEqual(SupporterSurfacePresentation(isSupporter: flag, result: .idle, productName: "A").showsTodayBadge,
                           HomeHeaderPresentation(isSupporter: flag).supporterBadge != nil)
        }
    }

    func testAccessibilityIdentifiers() {
        XCTAssertEqual(SupporterAccessibility.section, "settings.section.support")
        XCTAssertEqual(SupporterAccessibility.card, "settings.support")
        XCTAssertEqual(SupporterAccessibility.badge, "home.supporterBadge")
        XCTAssertTrue(SupporterAccessibility.cardCombinesTitleAndDetail)
        XCTAssertFalse(SupporterAccessibility.resultCombinedWithCard)
    }
}
