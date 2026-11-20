import Foundation
import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchStrengthPreviewDefaultsTests {
    @Test func freshInstallFallsBackToEightByEightAndOneMinute() {
        #expect(WatchStrengthPreviewDefaults.repPattern(stored: "") == [8, 8, 8])
        #expect(WatchStrengthPreviewDefaults.repsText([]) == "8-8-8")
        #expect(WatchStrengthPreviewDefaults.restSeconds(stored: 0) == 60)
        #expect(WatchStrengthPreviewDefaults.restText(0) == "1 min")
        #expect(WatchStrengthPreviewDefaults.partnerNames(stored: "", launchPartners: []) == [])
        #expect(WatchStrengthPreviewDefaults.partnersText([]) == "No partner")
    }

    @Test func lastUsedValuesAreStatedVerbatim() {
        #expect(WatchStrengthPreviewDefaults.repPattern(stored: "10-10-10") == [10, 10, 10])
        #expect(WatchStrengthPreviewDefaults.repsText([10, 10, 10]) == "10-10-10")
        #expect(WatchStrengthPreviewDefaults.restSeconds(stored: 90) == 90)
        #expect(WatchStrengthPreviewDefaults.restText(90) == "90 sec")
        #expect(WatchStrengthPreviewDefaults.restText(120) == "2 min")
        #expect(WatchStrengthPreviewDefaults.partnersText(["Audrey", "Sam"]) == "Audrey, Sam")
    }

    @Test func lastUsedPartnersWinOverTheLaunchesRoster() {
        #expect(WatchStrengthPreviewDefaults.partnerNames(stored: "Audrey\nSam",
                                                          launchPartners: ["Someone"]) == ["Audrey", "Sam"])
        #expect(WatchStrengthPreviewDefaults.partnerNames(stored: "",
                                                          launchPartners: ["Someone"],
                                                          previouslyChosen: true) == [])
    }
}
