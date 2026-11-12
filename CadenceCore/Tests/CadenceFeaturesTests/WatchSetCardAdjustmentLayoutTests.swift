import Testing
@testable import CadenceFeatures

@Suite struct WatchSetCardAdjustmentLayoutTests {
    @Test func inlineAdjustmentButtonsHaveCompactHeight() {
        #expect(WatchSetCardAdjustmentLayout.controlMinHeight == 28)
        #expect(WatchSetCardAdjustmentLayout.controlMinHeight < 36)
    }

    @Test func inlineAdjustmentRowUsesTightSpacing() {
        #expect(WatchSetCardAdjustmentLayout.horizontalSpacing == 4)
    }
}
