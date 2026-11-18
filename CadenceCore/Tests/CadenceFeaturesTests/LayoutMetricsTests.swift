import Testing
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

/// Field test 2026-08-18 issue 3. The action-button height and the page rhythm
/// have exactly one home; a view that hard-codes its own number is a regression.
struct LayoutMetricsTests {
    @Test func actionButtonHeightIsSingleSourced() {
        #expect(abs(LayoutMetrics.actionButtonHeight - 56) <= 0.001)
        #expect(LayoutMetrics.actionButtonHeight >= 44,
                "Full-width actions must clear the HIG 44pt touch target")
    }

    /// Field test 2026-08-19 #5 reversed the 2026-08-18 grouping: a tighter gap
    /// between two stacked Home actions than between the second action and the
    /// next card read as a layout bug, not as grouping. One page rhythm now.
    @Test func actionButtonSpacingMatchesSectionSpacing() {
        #expect(LayoutMetrics.actionButtonSpacing > 0)
        #expect(abs(LayoutMetrics.actionButtonSpacing - LayoutMetrics.sectionSpacing) <= 0.001,
                "Buttons and bounding boxes share one gap across every surface")
        #expect(LayoutMetrics.actionButtonCornerRadius > 0)
    }

    /// Every bounded card is the same shape, so a card on the live workout screen
    /// cannot drift from a card on Home (field test 2026-08-19 #5).
    @Test func cardCornerRadiusIsSingleSourced() {
        #expect(abs(LayoutMetrics.cardCornerRadius - 16) <= 0.001)
        #expect(abs(LayoutMetrics.cardCornerRadius - LayoutMetrics.actionButtonCornerRadius) <= 0.001,
                "A card and a full-width action share one corner radius")
    }

    @Test func sectionSpacingMatchesHomeRhythm() {
        #expect(abs(LayoutMetrics.sectionSpacing - 20) <= 0.001)
    }

    @Test func cardRhythmIsInternallyConsistent() {
        #expect(LayoutMetrics.cardHeadingSpacing <= LayoutMetrics.cardRowSpacing)
        #expect(LayoutMetrics.cardRowSpacing <= LayoutMetrics.sectionSpacing)
    }

    /// Field test 2026-08-18 issue 5: Workout Plan, Start Workout and Workout all
    /// read their vertical rhythm from the same constants Home uses, so there is
    /// one number to change rather than three hard-coded stacks.
    @Test func workoutSurfacesShareHomeSectionSpacing() {
        let homeSectionSpacing = LayoutMetrics.sectionSpacing
        for surface in ["Workout Plan", "Start Workout", "Workout"] {
            #expect(abs(LayoutMetrics.sectionSpacing - homeSectionSpacing) <= 0.001,
                    "\(surface) must use Home's section spacing")
            #expect(abs(LayoutMetrics.pagePadding - 16) <= 0.001,
                    "\(surface) must use Home's page padding")
        }
        #expect(LayoutMetrics.sectionSpacing > LayoutMetrics.cardRowSpacing,
                "Sections must read as further apart than rows inside a card")
    }

    @Test func pagePaddingIsSystemStandard() {
        #expect(abs(LayoutMetrics.pagePadding - 16) <= 0.001)
        #expect(abs(LayoutMetrics.cardPadding - 16) <= 0.001)
    }
}
