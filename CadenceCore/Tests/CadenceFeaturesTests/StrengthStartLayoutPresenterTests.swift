import XCTest
@testable import CadenceFeatures

/// Issue #620: the Strength start surface order, title and accessibility
/// contract are value-only policy that `WeightsStartView` renders verbatim.
final class StrengthStartLayoutPresenterTests: XCTestCase {
    private let expected: [StrengthStartItem] = [
        .suggestWorkout, .muscleCoverage, .quickStart,
        .previousWorkouts, .library, .heartRateMonitoring]

    func testOrderIsExactWithAndWithoutHistory() {
        XCTAssertEqual(StrengthStartLayoutPresenter.items(hasPrevious: false), expected)
        XCTAssertEqual(StrengthStartLayoutPresenter.items(hasPrevious: true), expected)
    }

    func testSuggestOccursOnceAndDirectlyPrecedesMuscleCoverage() {
        let items = StrengthStartLayoutPresenter.items(hasPrevious: true)
        XCTAssertEqual(items.filter { $0 == .suggestWorkout }.count, 1)
        XCTAssertEqual(items.first, .suggestWorkout)
        XCTAssertEqual(items.firstIndex(of: .muscleCoverage), 1)
    }

    func testTitleIsLocalizedAndOnlyForStrengthStart() {
        XCTAssertEqual(StrengthStartLayoutPresenter.navigationTitle(for: .strengthStart),
                       "Strength this week")
        XCTAssertEqual(StrengthStartLayoutPresenter.navigationTitle(for: .other("Strength")),
                       "Strength")
    }

    func testAccessibilityContractSeparatesSuggestFromCoverage() {
        let suggest = StrengthStartLayoutPresenter.accessibility(for: .suggestWorkout)
        XCTAssertEqual(suggest?.identifier, "weights.suggestWorkout")
        XCTAssertEqual(suggest?.label, "Suggest a Workout")
        XCTAssertFalse(suggest?.isHeading ?? true)
        let coverage = StrengthStartLayoutPresenter.accessibility(for: .muscleCoverage)
        XCTAssertEqual(coverage?.isHeading, true)
        XCTAssertNotEqual(coverage?.identifier, suggest?.identifier)
        XCTAssertFalse(coverage?.containsSuggestAction ?? true)
    }

    func testSuggestActionMapsToStrengthIntentOnly() {
        XCTAssertEqual(StrengthStartLayoutPresenter.suggestIntent, .strength)
    }
}
