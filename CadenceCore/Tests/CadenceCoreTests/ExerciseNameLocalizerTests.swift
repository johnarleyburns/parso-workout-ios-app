import XCTest
@testable import CadenceCore

final class ExerciseNameLocalizerTests: XCTestCase {
    func testSidecarLocalizesWithoutChangingCanonicalFallback() {
        let localizer = ExerciseNameLocalizer()
        XCTAssertEqual(localizer.localizedName(for: "Bench Press", locale: Locale(identifier: "de")), "Bankdrücken")
        XCTAssertEqual(localizer.localizedName(for: "New DB++ Movement", locale: Locale(identifier: "fr")), "New DB++ Movement")
        XCTAssertGreaterThanOrEqual(localizer.localizedExerciseCount, 10)
    }
}
