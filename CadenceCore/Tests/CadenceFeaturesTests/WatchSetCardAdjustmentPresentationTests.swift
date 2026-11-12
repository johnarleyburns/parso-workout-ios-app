import Testing
import CadenceCore
@testable import CadenceFeatures

@Suite struct WatchSetCardAdjustmentPresentationTests {
    @Test func poundsUseTheUnabbreviatedPluralCenterLabel() {
        #expect(WatchSetCardAdjustmentField.weight(.pounds).inlineLabel == "lbs")
    }

    @Test func kilogramsUseTheCompactKilogramCenterLabel() {
        #expect(WatchSetCardAdjustmentField.weight(.kilograms).inlineLabel == "kg")
    }

    @Test func repsUseTheDedicatedCenterLabel() {
        #expect(WatchSetCardAdjustmentField.reps.inlineLabel == "reps")
    }

    @Test(arguments: [
        WatchSetCardAdjustmentField.weight(.pounds),
        .weight(.kilograms),
        .reps
    ])
    func inlineLabelsAreShortAndNeverInstructional(_ field: WatchSetCardAdjustmentField) {
        let label = field.inlineLabel
        #expect(label.count <= 4)
        #expect(!label.contains("Crown"))
        #expect(!label.contains("…"))
        #expect(!label.contains("..."))
    }
}
