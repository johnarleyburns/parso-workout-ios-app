import Testing
@testable import Cadence_Watch_App_Watch_App

struct WatchHomeChromeTests {
    @Test("The launcher uses its product name as the native navigation title")
    func launcherNavigationTitleIsCladiron() {
        #expect(WatchHomeChrome.navigationTitle == "Cladiron")
    }
}
