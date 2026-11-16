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
    func testReleasedCatalogTranslationsAndEnglishAliasesAreAvailable() {
        let localizer = ExerciseNameLocalizer()
        for locale in ExerciseNameLocalizer.launchLocales where !locale.hasPrefix("en") {
            let name = localizer.localizedName(for: "Standing Toe Raise", locale: Locale(identifier: locale))
            XCTAssertNotEqual(name, "Standing Toe Raise", "Missing catalog translation for \(locale)")
        }
        XCTAssertEqual(localizer.localizedName(for: "Standing Toe Raise", locale: Locale(identifier: "de_AT")),
                       "Zehenheben im Stehen")
        XCTAssertTrue(localizer.searchTerms(for: "Hip Flexion with Band", locale: Locale(identifier: "es"))
            .contains("Banded March"))
        XCTAssertEqual(localizer.localizedName(for: "External Rotation", locale: Locale(identifier: "en")),
                       "Side-Lying Dumbbell External Rotation")
    }

}
