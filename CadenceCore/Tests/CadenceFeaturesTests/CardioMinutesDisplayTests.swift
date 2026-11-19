import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct CardioMinutesDisplayTests {
    @Test func loggedMinutesFormatsZeroFractionalAndNonZeroValues() {
        #expect(CardioMinutesDisplay.logged(0) == "0 min")
        #expect(CardioMinutesDisplay.logged(12.4) == "12 min")
        #expect(CardioMinutesDisplay.logged(12.5) == "13 min")
    }

    @Test func moderateEquivalentFormatsActualAndTarget() {
        #expect(CardioMinutesDisplay.moderateEquivalent(0, target: 150) == "0 of 150 min")
        #expect(CardioMinutesDisplay.moderateEquivalent(157.6, target: 150) == "158 of 150 min")
    }

    @Test func unclassifiedAndZoneValuesNeverExposeSourceExpressions() {
        let values = [
            CardioMinutesDisplay.unclassified(4.2),
            CardioMinutesDisplay.zone(7.8)
        ]
        #expect(values == ["4 min could not be intensity-classified", "8 min"])
        #expect(!values.joined(separator: " ").contains("dashboard.cardioDetail"))
        #expect(!values.joined(separator: " ").contains("Int("))
    }

    @Test func unattributedNamesTheRealThresholdWhenKnown() {
        #expect(CardioMinutesDisplay.unattributed(4.2, thresholdBPM: 102.4)
                       == "4 min unattributed — below minimum attribution HR of 102")
    }

    @Test func unattributedFallsBackToUnclassifiedWordingWithoutAThreshold() {
        #expect(CardioMinutesDisplay.unattributed(4.2, thresholdBPM: nil)
                       == CardioMinutesDisplay.unclassified(4.2))
    }
}

struct WeeklyCardioProgressTests {
    @Test func tintRolesUseMinimumAndTarget() {
        #expect(WeeklyCardioProgress.tintRole(for: 0) == .red)
        #expect(WeeklyCardioProgress.tintRole(for: 149) == .yellow)
        #expect(WeeklyCardioProgress.tintRole(for: 150) == .lightGreen)
        #expect(WeeklyCardioProgress.tintRole(for: 299) == .lightGreen)
        #expect(WeeklyCardioProgress.tintRole(for: 300) == .green)
    }
}
