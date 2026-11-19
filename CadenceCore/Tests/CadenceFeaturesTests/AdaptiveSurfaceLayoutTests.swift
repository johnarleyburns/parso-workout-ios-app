import Testing
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct AdaptiveSurfaceLayoutTests {
    @Test func regularWidthUsesTwoColumnsAtReadableSizes() {
        #expect(AdaptiveSurfaceLayout.resolve(isRegularWidth: true,
                                               isAccessibilitySize: false)
                == .twoColumn)
    }

    @Test func accessibilitySizeUsesFullWidthEvenOnRegularCanvas() {
        #expect(AdaptiveSurfaceLayout.resolve(isRegularWidth: true,
                                               isAccessibilitySize: true)
                == .stacked)
    }

    @Test func compactWidthRemainsStacked() {
        #expect(AdaptiveSurfaceLayout.resolve(isRegularWidth: false,
                                               isAccessibilitySize: false)
                == .stacked)
    }
}
