import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WeeklySetProgressTests {
    @Test func zonesUseExactFourEightAndTwelveSetBoundaries() {
        #expect(WeeklySetProgress.zone(for: 0) == .belowMinimum)
        #expect(WeeklySetProgress.zone(for: 3.5) == .belowMinimum)
        #expect(WeeklySetProgress.zone(for: 4) == .building)
        #expect(WeeklySetProgress.zone(for: 7.5) == .building)
        #expect(WeeklySetProgress.zone(for: 8) == .productive)
        #expect(WeeklySetProgress.zone(for: 12) == .productive)
        #expect(WeeklySetProgress.zone(for: 12.5) == .aboveMaximum)
        #expect(WeeklySetProgress.zone(for: -1) == .belowMinimum)
    }

    @Test func normalizedSetsClampAtZeroAndTwelve() {
        #expect(WeeklySetProgress.normalized(-1) == 0)
        #expect(WeeklySetProgress.normalized(0) == 0)
        #expect(abs(WeeklySetProgress.normalized(3.5) - 3.5 / 12) <= 0.0001)
        #expect(WeeklySetProgress.normalized(12) == 1)
        #expect(WeeklySetProgress.normalized(12.5) == 1)
    }

    @Test func zonesExposeOnlySemanticTintRoles() {
        #expect(WeeklySetZone.belowMinimum.tintRole == .red)
        #expect(WeeklySetZone.building.tintRole == .yellow)
        #expect(WeeklySetZone.productive.tintRole == .green)
        #expect(WeeklySetZone.aboveMaximum.tintRole == .red)
    }
}
