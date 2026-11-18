import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WeeklyActivityColorTests {
    @Test func activityPalettesAreDistinctWithinEveryBand() {
        for role: WeeklySetTintRole in [.red, .yellow, .lightGreen, .green] {
            let strength = WeeklyActivityPalette.color(role, cardio: false)
            let cardio = WeeklyActivityPalette.color(role, cardio: true)
            let distance = abs(strength.red - cardio.red) + abs(strength.green - cardio.green) + abs(strength.blue - cardio.blue)
            #expect(distance > 0.3)
        }
    }

    @Test func absoluteStrengthBoundaries() {
        for (value, expected): (Double, WeeklySetTintRole) in [
            (0, .red), (1, .yellow), (127.9, .yellow),
            (128, .lightGreen), (191.9, .lightGreen), (192, .green), (300, .green)
        ] {
            #expect(WeeklyActivityColor.strength(value) == expected)
        }
    }

    @Test func absoluteCardioBoundaries() {
        for (value, expected): (Double, WeeklySetTintRole) in [
            (0, .red), (0.1, .yellow), (149.9, .yellow),
            (150, .lightGreen), (299.9, .lightGreen), (300, .green)
        ] {
            #expect(WeeklyActivityColor.cardio(value) == expected)
        }
    }
}
