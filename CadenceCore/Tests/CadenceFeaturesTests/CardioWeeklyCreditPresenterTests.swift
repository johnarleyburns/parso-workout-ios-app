import XCTest
import CadenceCore
@testable import CadenceFeatures

/// Issue #619: the start-mode Cardio picker shows this week's
/// moderate-equivalent credit as "m of n min credit" from an injected,
/// value-only display model.
final class CardioWeeklyCreditPresenterTests: XCTestCase {

    // MARK: Mapping (issue TDD 1-3)

    func testMapsPartialCreditToTextProgressAndYellow() {
        let display = CardioWeeklyCreditPresenter.make(creditedMinutes: 158, targetMinutes: 300)
        XCTAssertEqual(display.creditedMinutes, 158)
        XCTAssertEqual(display.targetMinutes, 300)
        XCTAssertEqual(display.visibleText, "158 of 300 min credit")
        XCTAssertEqual(display.normalizedProgress, 158.0 / 300.0)
        XCTAssertEqual(display.tintRole, .yellow)
    }

    func testZeroCreditIsEmptyRingAndRed() {
        let display = CardioWeeklyCreditPresenter.make(creditedMinutes: 0, targetMinutes: 300)
        XCTAssertEqual(display.visibleText, "0 of 300 min credit")
        XCTAssertEqual(display.normalizedProgress, 0)
        XCTAssertEqual(display.tintRole, .red)
    }

    func testCreditAboveTargetKeepsNumeratorButClampsRingAndIsGreen() {
        let display = CardioWeeklyCreditPresenter.make(creditedMinutes: 340, targetMinutes: 300)
        XCTAssertEqual(display.creditedMinutes, 340)
        XCTAssertEqual(display.visibleText, "340 of 300 min credit")
        XCTAssertEqual(display.accessibilityValue, "340 of 300 minutes credit")
        XCTAssertEqual(display.normalizedProgress, 1)
        XCTAssertEqual(display.tintRole, .green)
    }

    // MARK: Rounding (issue TDD 4)

    /// Home rounds the credit with `Double.rounded()` (half away from zero).
    /// The picker uses the same rounded integer for the visible text, the
    /// VoiceOver value AND the ring fraction, so none of them can disagree.
    func testFractionalCreditUsesDashboardRoundingForTextValueAndRing() {
        let up = CardioWeeklyCreditPresenter.make(creditedMinutes: 149.5, targetMinutes: 300)
        XCTAssertEqual(up.creditedMinutes, 150)
        XCTAssertEqual(up.visibleText, "150 of 300 min credit")
        XCTAssertEqual(up.accessibilityValue, "150 of 300 minutes credit")
        XCTAssertEqual(up.normalizedProgress, 150.0 / 300.0)

        let down = CardioWeeklyCreditPresenter.make(creditedMinutes: 149.49, targetMinutes: 300)
        XCTAssertEqual(down.creditedMinutes, 149)
        XCTAssertEqual(down.visibleText, "149 of 300 min credit")
        XCTAssertEqual(down.accessibilityValue, "149 of 300 minutes credit")
        XCTAssertEqual(down.normalizedProgress, 149.0 / 300.0)

        // The ring completes exactly when the text reads "300 of 300".
        let nearlyFull = CardioWeeklyCreditPresenter.make(creditedMinutes: 299.5, targetMinutes: 300)
        XCTAssertEqual(nearlyFull.visibleText, "300 of 300 min credit")
        XCTAssertEqual(nearlyFull.normalizedProgress, 1)
    }

    func testFractionalValuesMatchTheHomeDashboardText() {
        for credit in [0.4, 149.5, 157.5, 299.5, 340.49] {
            let state = dashboard(weeklyCardio: summary(actual: credit, vigorous: 0,
                                                        credit: credit, target: 300))
            let display = CardioWeeklyCreditPresenter.make(detail: state.cardioDetail)
            XCTAssertEqual(display.visibleText, state.cardio.displayText, "credit \(credit)")
        }
    }

    // MARK: Invalid input (issue TDD 5)

    func testInvalidTargetFallsBackToGuidelineTargetWithoutNaN() {
        for target in [0, -10, 0.4, Double.nan, Double.infinity, -Double.infinity] {
            let display = CardioWeeklyCreditPresenter.make(creditedMinutes: 158, targetMinutes: target)
            XCTAssertEqual(display.targetMinutes, Int(WeeklyCardioProgress.target), "target \(target)")
            XCTAssertEqual(display.visibleText, "158 of 300 min credit", "target \(target)")
            XCTAssertTrue(display.normalizedProgress.isFinite, "target \(target)")
            XCTAssertTrue((0...1).contains(display.normalizedProgress), "target \(target)")
            XCTAssertEqual(display.normalizedProgress, 158.0 / 300.0, "target \(target)")
        }
    }

    func testInvalidCreditIsTreatedAsZero() {
        for credit in [-5, Double.nan, Double.infinity, -Double.infinity] {
            let display = CardioWeeklyCreditPresenter.make(creditedMinutes: credit, targetMinutes: 300)
            XCTAssertEqual(display.creditedMinutes, 0, "credit \(credit)")
            XCTAssertEqual(display.visibleText, "0 of 300 min credit", "credit \(credit)")
            XCTAssertEqual(display.normalizedProgress, 0, "credit \(credit)")
            XCTAssertEqual(display.tintRole, .red, "credit \(credit)")
        }
    }

    // MARK: Tint boundaries (issue TDD 6)

    func testTintBoundariesFollowTheWeeklyCardioPolicy() {
        func role(_ credit: Double) -> WeeklySetTintRole {
            CardioWeeklyCreditPresenter.make(creditedMinutes: credit, targetMinutes: 300).tintRole
        }
        XCTAssertEqual(role(149.999), .red)
        XCTAssertEqual(role(150), .yellow)
        XCTAssertEqual(role(299.999), .yellow)
        XCTAssertEqual(role(300), .green)
    }

    // MARK: Home snapshot adapter (issue TDD 9)

    /// 60 minutes of vigorous work earns 120 moderate-equivalent minutes.
    /// The picker must show the credit (120), never the clock minutes (60),
    /// and the active target from the same weekly summary.
    func testHomeSnapshotSuppliesModerateEquivalentCreditAndActiveTargetUnchanged() {
        let state = dashboard(weeklyCardio: summary(actual: 60, vigorous: 60, credit: 120, target: 150))
        XCTAssertEqual(state.cardioDetail.loggedMinutes, 60)
        XCTAssertEqual(state.cardioDetail.moderateEquivalentMinutes, 120)
        XCTAssertEqual(state.cardioDetail.targetMinutes, 150)

        let display = CardioWeeklyCreditPresenter.make(detail: state.cardioDetail)
        XCTAssertEqual(display, CardioWeeklyCreditPresenter.make(creditedMinutes: 120, targetMinutes: 150))
        XCTAssertEqual(display.creditedMinutes, 120)
        XCTAssertNotEqual(display.creditedMinutes, 60)
        XCTAssertEqual(display.targetMinutes, 150)
        XCTAssertEqual(display.visibleText, "120 of 150 min credit")
        XCTAssertEqual(display.visibleText, state.cardio.displayText)
    }

    func testColdStartUsesTheExistingGuidelineTargetFallback() {
        let state = dashboard(weeklyCardio: nil)
        let display = CardioWeeklyCreditPresenter.make(detail: state.cardioDetail)
        XCTAssertEqual(display.targetMinutes, Int(WeeklyCardioProgress.target))
        XCTAssertEqual(display.visibleText, state.cardio.displayText)
    }

    // MARK: Accessibility contract (issue TDD 11)

    func testAccessibilityContractCarriesLabelValueAndStableIdentifiers() {
        let display = CardioWeeklyCreditPresenter.make(creditedMinutes: 158, targetMinutes: 300)
        XCTAssertEqual(display.accessibilityLabel, "Cardio this week")
        XCTAssertEqual(display.accessibilityValue, "158 of 300 minutes credit")
        XCTAssertEqual(CardioWeeklyCreditDisplay.Identifier.surface, "cardioPicker.weeklyCredit")
        XCTAssertEqual(CardioWeeklyCreditDisplay.Identifier.ring, "cardioPicker.weeklyCredit.ring")
        XCTAssertEqual(CardioWeeklyCreditDisplay.Identifier.value, "cardioPicker.weeklyCredit.value")
    }

    // MARK: Fixtures

    private func summary(actual: Double, vigorous: Double, credit: Double,
                         target: Double) -> WeeklyCardioSummary {
        WeeklyCardioSummary(
            actualMinutes: actual, belowModerateMinutes: 0,
            moderateMinutes: actual - vigorous, vigorousMinutes: vigorous,
            moderateEquivalentMinutes: credit, unclassifiedMinutes: 0,
            zoneMinutes: [:], guidelineTarget: target,
            algorithmVersion: CardioAlgorithmVersion.hrrGuidelineV1)
    }

    private func dashboard(weeklyCardio: WeeklyCardioSummary?) -> HomeDashboardState {
        let snapshot = CoachSnapshotBuilder.build(
            sessions: [], cardio: [], assessments: [], hasPainToday: false,
            goal: .strength, experience: .intermediate, formula: .epley,
            schedulePreferences: .default, profile: .empty, now: Date())
        return HomeDashboardPresenter.make(
            snapshot: snapshot, schedule: .default, goal: .strength,
            experience: .intermediate, userAge: 30,
            weeklyCardio: weeklyCardio, activityDose: nil)
    }
}
