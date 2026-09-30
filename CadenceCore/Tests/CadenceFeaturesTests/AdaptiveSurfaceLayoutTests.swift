import XCTest
@testable import CadenceFeatures

final class AdaptiveSurfaceLayoutTests: XCTestCase {
    func testRegularWidthUsesTwoColumnsAtReadableSizes() {
        XCTAssertEqual(AdaptiveSurfaceLayout.resolve(isRegularWidth: true,
                                                      isAccessibilitySize: false),
                       .twoColumn)
    }

    func testAccessibilitySizeUsesFullWidthEvenOnRegularCanvas() {
        XCTAssertEqual(AdaptiveSurfaceLayout.resolve(isRegularWidth: true,
                                                      isAccessibilitySize: true),
                       .stacked)
    }

    func testCompactWidthRemainsStacked() {
        XCTAssertEqual(AdaptiveSurfaceLayout.resolve(isRegularWidth: false,
                                                      isAccessibilitySize: false),
                       .stacked)
    }
}
