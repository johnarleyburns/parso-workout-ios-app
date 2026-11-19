import Testing
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WeeklyIntentPresenterTests {
    private func progress(_ c: Double, _ t: Double, _ text: String = "x") -> HomeDashboardState.Progress {
        .init(completed: c, target: t, displayText: text, normalized: 0)
    }

    @Test func strengthRingReflectsCompletedOverTarget() {
        let d = WeeklyIntentPresenter.make(strength: progress(6, 12), cardio: progress(0, 150))
        #expect(d.strengthRing.normalizedProgress == 0.5)
    }

    @Test func concentricRingsKeepStrengthAndCardioProgressIndependent() {
        let display = WeeklyIntentPresenter.make(
            strength: progress(24, 48, "24 of 48 sets"),
            cardio: progress(90, 150, "90 of 150 min credit"))

        #expect(display.strengthRing.normalizedProgress == 0.5)
        #expect(display.cardioRing.normalizedProgress == 0.6)
        #expect(display.strengthRing.valueText == "24 of 48 sets")
        #expect(display.cardioRing.valueText == "90 of 150 min credit")
    }

    @Test func ringsClampAtFullWithoutExceeding100Percent() {
        let d = WeeklyIntentPresenter.make(strength: progress(20, 12, "20 of 12 sets"), cardio: progress(0, 150))
        #expect(d.strengthRing.normalizedProgress == 1.0)
        #expect(d.strengthRing.valueText == "20 of 12 sets")
        #expect(d.strengthRing.tintRole == .yellow)
    }

    @Test func zeroHistoryRendersZeroNotNil() {
        let d = WeeklyIntentPresenter.make(strength: progress(0, 36), cardio: progress(0, 150))
        #expect(d.strengthRing.normalizedProgress == 0)
        #expect(d.strengthRing.tintRole == .red)
    }

    @Test func targetZeroDoesNotDivideByZero() {
        let d = WeeklyIntentPresenter.make(strength: progress(5, 0), cardio: progress(0, 0))
        #expect(d.strengthRing.normalizedProgress == 0)
        #expect(d.cardioRing.normalizedProgress == 0)
    }
}
