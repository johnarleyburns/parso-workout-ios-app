import Foundation
import Testing
@testable import CadenceCore

struct ExerciseNameLocalizerTests {
    @Test func sidecarLocalizesWithoutChangingCanonicalFallback() {
        let localizer = ExerciseNameLocalizer()
        #expect(localizer.localizedName(for: "Bench Press", locale: Locale(identifier: "de")) == "Bankdrücken")
        #expect(localizer.localizedName(for: "New DB++ Movement", locale: Locale(identifier: "fr")) == "New DB++ Movement")
        #expect(localizer.localizedExerciseCount >= 10)
    }

    @Test func regionAndScriptLocalesResolveToSidecarTags() {
        let localizer = ExerciseNameLocalizer()
        #expect(localizer.localizedName(for: "Bench Press", locale: Locale(identifier: "pt_BR")) == "Supino")
        #expect(localizer.localizedName(for: "Bench Press", locale: Locale(identifier: "zh-Hans_CN")) == "卧推")
        #expect(localizer.localizedName(for: "Bench Press", locale: Locale(identifier: "zh_TW")) == "臥推")
        #expect(localizer.localizedName(for: "Bench Press", locale: Locale(identifier: "de_AT")) == "Bankdrücken")
    }
    @Test func releasedCatalogTranslationsAndEnglishAliasesAreAvailable() {
        let localizer = ExerciseNameLocalizer()
        for locale in ExerciseNameLocalizer.launchLocales where !locale.hasPrefix("en") {
            let name = localizer.localizedName(for: "Standing Toe Raise", locale: Locale(identifier: locale))
            #expect(name != "Standing Toe Raise", "Missing catalog translation for \(locale)")
        }
        #expect(localizer.localizedName(for: "Standing Toe Raise", locale: Locale(identifier: "de_AT")) ==
                       "Zehenheben im Stehen")
        #expect(localizer.searchTerms(for: "Hip Flexion with Band", locale: Locale(identifier: "es"))
            .contains("Banded March"))
        #expect(localizer.localizedName(for: "External Rotation", locale: Locale(identifier: "en")) ==
                       "Side-Lying Dumbbell External Rotation")
    }

}
