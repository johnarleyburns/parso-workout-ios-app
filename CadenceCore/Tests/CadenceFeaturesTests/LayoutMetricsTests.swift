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

    /// Field test 2026-08-19 #5 reversed the 2026-08-18 grouping: a tighter gap
    /// between two stacked Home actions than between the second action and the
    /// next card read as a layout bug, not as grouping. One page rhythm now.
    func testActionButtonSpacingMatchesSectionSpacing() {
        XCTAssertGreaterThan(LayoutMetrics.actionButtonSpacing, 0)
        XCTAssertEqual(LayoutMetrics.actionButtonSpacing, LayoutMetrics.sectionSpacing, accuracy: 0.001,
                       "Buttons and bounding boxes share one gap across every surface")
        XCTAssertGreaterThan(LayoutMetrics.actionButtonCornerRadius, 0)
    }

    /// Every bounded card is the same shape, so a card on the live workout screen
    /// cannot drift from a card on Home (field test 2026-08-19 #5).
    func testCardCornerRadiusIsSingleSourced() {
        XCTAssertEqual(LayoutMetrics.cardCornerRadius, 16, accuracy: 0.001)
        XCTAssertEqual(LayoutMetrics.cardCornerRadius, LayoutMetrics.actionButtonCornerRadius,
                       accuracy: 0.001,
                       "A card and a full-width action share one corner radius")
    }

    func testSectionSpacingMatchesHomeRhythm() {
        XCTAssertEqual(LayoutMetrics.sectionSpacing, 20, accuracy: 0.001)
    }

    func testCardRhythmIsInternallyConsistent() {
        XCTAssertLessThanOrEqual(LayoutMetrics.cardHeadingSpacing, LayoutMetrics.cardRowSpacing)
        XCTAssertLessThanOrEqual(LayoutMetrics.cardRowSpacing, LayoutMetrics.sectionSpacing)
    }

    /// Field test 2026-08-18 issue 5: Workout Plan, Start Workout and Workout all
    /// read their vertical rhythm from the same constants Home uses, so there is
    /// one number to change rather than three hard-coded stacks.
    func testWorkoutSurfacesShareHomeSectionSpacing() {
        let homeSectionSpacing = LayoutMetrics.sectionSpacing
        for surface in ["Workout Plan", "Start Workout", "Workout"] {
            XCTAssertEqual(LayoutMetrics.sectionSpacing, homeSectionSpacing, accuracy: 0.001,
                           "\(surface) must use Home's section spacing")
            XCTAssertEqual(LayoutMetrics.pagePadding, 16, accuracy: 0.001,
                           "\(surface) must use Home's page padding")
        }
        XCTAssertGreaterThan(LayoutMetrics.sectionSpacing, LayoutMetrics.cardRowSpacing,
                             "Sections must read as further apart than rows inside a card")
    }

    func testPagePaddingIsSystemStandard() {
        XCTAssertEqual(LayoutMetrics.pagePadding, 16, accuracy: 0.001)
        XCTAssertEqual(LayoutMetrics.cardPadding, 16, accuracy: 0.001)
    }
}
