import XCTest
@testable import CadenceFeatures

final class WeeklyIntentPresenterTests: XCTestCase {
    private func progress(_ c: Double, _ t: Double, _ text: String = "x") -> HomeDashboardState.Progress {
        .init(completed: c, target: t, displayText: text, normalized: 0)
    }

    func testStrengthRingReflectsCompletedOverTarget() {
        let d = WeeklyIntentPresenter.make(strength: progress(6, 12), cardio: progress(0, 150))
        XCTAssertEqual(d.strengthRing.normalizedProgress, 0.5)
    }

    func testRingsClampAtFullWithoutExceeding100Percent() {
        let d = WeeklyIntentPresenter.make(strength: progress(20, 12, "20 of 12 sets"), cardio: progress(0, 150))
        XCTAssertEqual(d.strengthRing.normalizedProgress, 1.0)
        XCTAssertEqual(d.strengthRing.valueText, "20 of 12 sets")
        XCTAssertEqual(d.strengthRing.tintRole, .green)
    }

    func testZeroHistoryRendersZeroNotNil() {
        let d = WeeklyIntentPresenter.make(strength: progress(0, 36), cardio: progress(0, 150))
        XCTAssertEqual(d.strengthRing.normalizedProgress, 0)
        XCTAssertEqual(d.strengthRing.tintRole, .red)
    }

    func testTargetZeroDoesNotDivideByZero() {
        let d = WeeklyIntentPresenter.make(strength: progress(5, 0), cardio: progress(0, 0))
        XCTAssertEqual(d.strengthRing.normalizedProgress, 0)
        XCTAssertEqual(d.cardioRing.normalizedProgress, 0)
    }
}
