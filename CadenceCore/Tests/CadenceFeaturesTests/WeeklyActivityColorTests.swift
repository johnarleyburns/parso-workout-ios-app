import XCTest
@testable import CadenceFeatures

final class WeeklyActivityColorTests: XCTestCase {
    func testAbsoluteStrengthBoundaries() {
        for (value, expected): (Double, WeeklySetTintRole) in [
            (0, .red), (1, .yellow), (127.9, .yellow),
            (128, .lightGreen), (191.9, .lightGreen), (192, .green), (300, .green)
        ] {
            XCTAssertEqual(WeeklyActivityColor.strength(value), expected)
        }
    }

    func testAbsoluteCardioBoundaries() {
        for (value, expected): (Double, WeeklySetTintRole) in [
            (0, .red), (0.1, .yellow), (149.9, .yellow),
            (150, .lightGreen), (299.9, .lightGreen), (300, .green)
        ] {
            XCTAssertEqual(WeeklyActivityColor.cardio(value), expected)
        }
    }
}
