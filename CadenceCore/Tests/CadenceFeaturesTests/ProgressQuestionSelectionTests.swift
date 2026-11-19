import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct ProgressQuestionSelectionTests {
    @Test func strengthOverTimeIsTheDefault() {
        #expect(ProgressQuestionSelection().selected == .strengthOverTime)
    }

    @Test func selectingAnotherQuestionReplacesTheCurrentSummary() {
        var selection = ProgressQuestionSelection()

        selection.select(.personalRecords)
        #expect(selection.selected == .personalRecords)

        selection.select(.intensity)
        #expect(selection.selected == .intensity)
    }

    @Test func alphabeticalContainsEveryCaseExactlyOnce() {
        let list = ProgressQuestion.alphabetical
        #expect(list.count == ProgressQuestion.allCases.count - 1)
        #expect(Set(list) == Set(ProgressQuestion.allCases.filter { $0 != .workoutHistory }))
        #expect(list.contains(.observations))
    }

    @Test func historyLivesOutsideProgress() {
        #expect(!ProgressQuestion.alphabetical.contains(.workoutHistory))
        #expect(ProgressQuestionSelection(selected: .workoutHistory).selected == .strengthOverTime)
    }

    @Test func alphabeticalIsLocalizedLabelSorted() {
        let names = ProgressQuestion.alphabetical.map(\.displayName)
        let sorted = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        #expect(names == sorted)
    }

    @Test func persistedRawValuesRestoreSelection() {
        let suite = "ProgressQuestionSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for (raw, expected) in [("workoutHistory", ProgressQuestion.strengthOverTime),
                                ("observations", .observations),
                                ("bogus", .strengthOverTime)] {
            defaults.set(raw, forKey: ProgressQuestionSelection.persistenceKey)
            #expect(ProgressQuestionSelection.persisted(defaults: defaults).selected == expected)
        }
    }

    @Test func selectionPersistsAndDefaultsToStrengthOverTime() {
        let suite = "ProgressQuestionSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(ProgressQuestionSelection.persisted(defaults: defaults).selected
                       == .strengthOverTime)
        let selection = ProgressQuestionSelection(selected: .personalRecords)
        selection.persist(defaults: defaults)
        #expect(ProgressQuestionSelection.persisted(defaults: defaults).selected
                       == .personalRecords)
    }

    @Test func onlyWorkoutHistoryHostsItsOwnList() {
        #expect(ProgressQuestion.allCases.filter { $0.hostsOwnList } == [.workoutHistory])
    }

    @Test func selectingHistoryKeepsPickerStateStable() {
        var selection = ProgressQuestionSelection(selected: .tests)
        selection.select(.workoutHistory)
        #expect(selection.selected == .strengthOverTime)
        selection.select(.tests)
        #expect(selection.selected == .tests)
    }
}
