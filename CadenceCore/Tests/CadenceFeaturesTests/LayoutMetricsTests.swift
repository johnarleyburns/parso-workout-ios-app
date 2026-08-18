import XCTest
@testable import CadenceFeatures

/// Field test 2026-08-18 issue 3. The action-button height and the page rhythm
/// have exactly one home; a view that hard-codes its own number is a regression.
final class LayoutMetricsTests: XCTestCase {
    func testActionButtonHeightIsSingleSourced() {
        XCTAssertEqual(LayoutMetrics.actionButtonHeight, 56, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(LayoutMetrics.actionButtonHeight, 44,
                                    "Full-width actions must clear the HIG 44pt touch target")
    }

    func testActionButtonSpacingIsPositiveAndSmallerThanSectionSpacing() {
        XCTAssertGreaterThan(LayoutMetrics.actionButtonSpacing, 0)
        XCTAssertLessThan(LayoutMetrics.actionButtonSpacing, LayoutMetrics.sectionSpacing,
                          "Stacked actions read as one group, so they sit tighter than sections")
        XCTAssertGreaterThan(LayoutMetrics.actionButtonCornerRadius, 0)
    }

    func testSectionSpacingMatchesHomeRhythm() {
        XCTAssertEqual(LayoutMetrics.sectionSpacing, 20, accuracy: 0.001)
    }

    func testCardRhythmIsInternallyConsistent() {
        XCTAssertLessThanOrEqual(LayoutMetrics.cardHeadingSpacing, LayoutMetrics.cardRowSpacing)
        XCTAssertLessThanOrEqual(LayoutMetrics.cardRowSpacing, LayoutMetrics.sectionSpacing)
    }

    func testPagePaddingIsSystemStandard() {
        XCTAssertEqual(LayoutMetrics.pagePadding, 16, accuracy: 0.001)
        XCTAssertEqual(LayoutMetrics.cardPadding, 16, accuracy: 0.001)
    }
}
