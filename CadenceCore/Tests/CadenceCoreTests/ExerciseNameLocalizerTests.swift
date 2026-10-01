import XCTest
@testable import CadenceCore

final class ExerciseNameLocalizerTests: XCTestCase {
    func testSidecarLocalizesWithoutChangingCanonicalFallback() {
        let localizer = ExerciseNameLocalizer()
        XCTAssertEqual(localizer.localizedName(for: "Bench Press", locale: Locale(identifier: "de")), "Bankdrücken")
        XCTAssertEqual(localizer.localizedName(for: "New DB++ Movement", locale: Locale(identifier: "fr")), "New DB++ Movement")
        XCTAssertGreaterThanOrEqual(localizer.localizedExerciseCount, 10)
    }

    func testRegionAndScriptLocalesResolveToSidecarTags() {
        let localizer = ExerciseNameLocalizer()
        XCTAssertEqual(localizer.localizedName(for: "Bench Press", locale: Locale(identifier: "pt_BR")), "Supino")
        XCTAssertEqual(localizer.localizedName(for: "Bench Press", locale: Locale(identifier: "zh-Hans_CN")), "卧推")
        XCTAssertEqual(localizer.localizedName(for: "Bench Press", locale: Locale(identifier: "zh_TW")), "臥推")
        XCTAssertEqual(localizer.localizedName(for: "Bench Press", locale: Locale(identifier: "de_AT")), "Bankdrücken")
    }
}
