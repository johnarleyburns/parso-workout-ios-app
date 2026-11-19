import Testing
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct HomeHeaderPresentationTests {
    @Test func supporterProducesAchievementBadge() throws {
        let badge = try #require(HomeHeaderPresentation(isSupporter: true).supporterBadge)
        #expect(badge.text == "Supporter")
        #expect(badge.accessibilityLabel == "Supporter")
        #expect(badge.systemImage == "heart.fill")
        #expect(badge.tint == .achievement)
        #expect(badge.accessibilityIdentifier == "home.supporterBadge")
    }

    @Test func nonSupporterHasNoBadge() {
        #expect(HomeHeaderPresentation(isSupporter: false).supporterBadge == nil)
    }

    @Test func trailingItemsPlaceTheSupporterBadgeBeforeSettings() {
        #expect(HomeHeaderPresentation(isSupporter: true).trailingItems == [.supporterBadge, .settings])
        #expect(HomeHeaderPresentation(isSupporter: false).trailingItems == [.settings])
    }
}
