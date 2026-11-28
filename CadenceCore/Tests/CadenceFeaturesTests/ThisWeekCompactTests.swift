import Testing
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct ThisWeekCompactTests {
    private func display(strength: String, cardio: String) -> WeeklyIntentDisplay {
        WeeklyIntentDisplay(
            strengthRing: .init(normalizedProgress: 0.5, tintRole: .green,
                                valueText: strength, accessibilityLabel: "Strength", accessibilityValue: strength),
            cardioRing: .init(normalizedProgress: 0.4, tintRole: .green,
                              valueText: cardio, accessibilityLabel: "Cardio", accessibilityValue: cardio))
    }

    @Test func legendIsTwoLeftJustifiedRowsInStrengthThenCardioOrder() {
        let rows = ThisWeekCompactPresentation.rows(from: display(strength: "12/16 sets", cardio: "98/150 min"))
        #expect(rows.map(\.kind) == [.strength, .cardio])
        #expect(rows.map(\.value) == ["12/16 sets", "98/150 min"])
        #expect(rows.map(\.accessibilityIdentifier) == ["home.thisWeek.strength", "home.thisWeek.cardio"])
    }

    @Test func ringsAreSmallerThanThePreviousFullSizeCard() {
        #expect(ThisWeekCompactPresentation.ringDiameter <= 120)
        #expect(ThisWeekCompactPresentation.ringDiameter < 148)
    }
}
