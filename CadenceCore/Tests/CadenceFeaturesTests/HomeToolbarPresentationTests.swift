import Testing
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct HomeToolbarPresentationTests {
    @Test func menuIsHistoryThenTheWeekSurfacesThenSettings() {
        #expect(HomeToolbarPresentation.menu == [.history, .strengthWeek, .cardioWeek, .settings])
        #expect(HomeToolbarPresentation.menu.map(\.accessibilityIdentifier)
                == ["home.menu.history", "home.menu.strengthWeek",
                    "home.menu.cardioWeek", "home.menu.settings"])
    }

    @Test func strengthAndCardioAreNoLongerTabBarItems() {
        #expect(HomeToolbarPresentation.tabs == [.workout, .progress, .find])
        #expect(!HomeToolbarPresentation.tabs.map(\.rawValue).contains("strength"))
        #expect(!HomeToolbarPresentation.tabs.map(\.rawValue).contains("cardio"))
    }

    @Test func supporterBadgeIsLeadingOnly() {
        let supporter = HomeHeaderPresentation(isSupporter: true)
        #expect(supporter.leadingItems == [.supporterBadge])
        #expect(HomeHeaderPresentation(isSupporter: false).leadingItems.isEmpty)
        // The badge is never a trailing/menu item.
        #expect(!supporter.menuItems.map(\.rawValue).contains("supporterBadge"))
    }

    @Test func menuCoversEveryDestinationExactlyOnce() {
        #expect(Set(HomeToolbarPresentation.menu) == Set(HomeMenuDestination.allCases))
        #expect(HomeToolbarPresentation.menu.count == HomeMenuDestination.allCases.count)
    }

    @Test func visibleTabsCoverEveryRemainingTabExactlyOnce() {
        #expect(Set(HomeToolbarPresentation.tabs) == Set(RootTabItem.allCases))
    }
}
