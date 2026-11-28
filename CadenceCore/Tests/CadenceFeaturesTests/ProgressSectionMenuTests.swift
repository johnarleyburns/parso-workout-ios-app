import Testing
import CadenceFeatures
import CadenceWorkoutFeatures

struct ProgressSectionMenuTests {
    @Test func menuKeepsThePickerOrder() {
        let items = ProgressSectionMenu.items(for: ProgressQuestionSelection(selected: .strengthOverTime))
        #expect(items.map(\.question) == ProgressQuestion.alphabetical)
        #expect(items.count == ProgressQuestion.alphabetical.count)
    }

    @Test func exactlyOneItemIsSelectedAndItIsTheCurrentQuestion() {
        for question in ProgressQuestion.alphabetical {
            let items = ProgressSectionMenu.items(for: ProgressQuestionSelection(selected: question))
            let selected = items.filter(\.isSelected)
            #expect(selected.count == 1)
            #expect(selected.first?.question == question)
        }
    }

    @Test func selectionIdentifiersMatchTheOldChipIdentifiers() {
        let items = ProgressSectionMenu.items(for: ProgressQuestionSelection(selected: .consistency))
        #expect(items.first { $0.question == .strengthOverTime }?.accessibilityIdentifier
                == "progress.question.strengthOverTime")
    }
}
