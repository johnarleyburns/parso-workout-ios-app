import Testing
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct SupporterSurfacePresentationTests {
    @Test func trailingItemsOnlyIncludeBadgeBeforeSettingsForSupporter() {
        #expect(HomeHeaderPresentation(isSupporter: false).trailingItems == [.settings])
        #expect(HomeHeaderPresentation(isSupporter: true).trailingItems == [.supporterBadge, .settings])
    }

    @Test func badgeMetrics() throws {
        let badge = try #require(HomeHeaderPresentation(isSupporter: true).supporterBadge)
        #expect(badge.horizontalPadding == 10)
        #expect(badge.verticalPadding == 6)
    }

    @Test func cardCopy() {
        let a = SupporterSurfacePresentation(isSupporter: false, result: .idle, productName: "App")
        #expect(a.settingsTitle == "Contribute to Development")
        #expect(a.settingsDetail == "A one-time, optional $9.99 — every feature is already free")
        #expect(!a.showsTodayBadge)
        let b = SupporterSurfacePresentation(isSupporter: true, result: .idle, productName: "App")
        #expect(b.settingsTitle == "Thanks for supporting App")
        #expect(b.settingsDetail == "You have the Supporter badge")
        #expect(b.showsTodayBadge)
    }

    @Test func reducerPreventsDuplicatesAndRestores() {
        var s = SupporterPurchaseState()
        #expect(SupporterSurfacePresentation(isSupporter: false, result: s.result, productName: "A").isPurchaseEnabled)
        let first = s.begin()
        #expect(first)
        let second = s.begin()
        #expect(!second)
        #expect(!SupporterSurfacePresentation(isSupporter: false, result: s.result, productName: "A").isPurchaseEnabled)
        s.finish(.cancelledOrPending)
        #expect(s.result == .idle)
        let third = s.begin()
        #expect(third)
    }

    @Test func successAndFailureResults() {
        var s = SupporterPurchaseState()
        _ = s.begin(); s.finish(.verifiedSuccess)
        let ok = SupporterSurfacePresentation(isSupporter: true, result: s.result, productName: "App")
        #expect(ok.resultMessage == "Thank you for supporting App!")
        #expect(ok.showsTodayBadge)
        _ = s.begin(); s.finish(.failure(message: "boom"))
        let bad = SupporterSurfacePresentation(isSupporter: false, result: s.result, productName: "App")
        #expect(bad.resultMessage == "Purchase failed: boom")
        #expect(!bad.showsTodayBadge)
        #expect(bad.isPurchaseEnabled)
    }

    @Test func cancelKeepsPriorSuccessMessage() {
        var s = SupporterPurchaseState()
        _ = s.begin(); s.finish(.verifiedSuccess)
        _ = s.begin(); s.finish(.cancelledOrPending)
        #expect(s.result == .succeeded)
    }

    @Test func bothSurfacesObserveSameFlag() {
        for flag in [false, true] {
            #expect(SupporterSurfacePresentation(isSupporter: flag, result: .idle, productName: "A").showsTodayBadge ==
                           (HomeHeaderPresentation(isSupporter: flag).supporterBadge != nil))
        }
    }

    @Test func accessibilityIdentifiers() {
        #expect(SupporterAccessibility.section == "settings.section.support")
        #expect(SupporterAccessibility.card == "settings.support")
        #expect(SupporterAccessibility.badge == "home.supporterBadge")
        #expect(SupporterAccessibility.cardCombinesTitleAndDetail)
        #expect(!SupporterAccessibility.resultCombinedWithCard)
    }
}
