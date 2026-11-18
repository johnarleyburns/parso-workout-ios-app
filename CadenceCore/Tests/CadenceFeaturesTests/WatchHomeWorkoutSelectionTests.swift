import Foundation
import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchHomeWorkoutSelectionTests {
    @Test func strengthIsDefaultWithWatchSpecificNamesAndIcons() {
        let state = WatchHomeWorkoutSelection()
        #expect(state.mode == .strength)
        #expect(state.choices.map { state.title(for: $0) } == ["Personalized", "Previous", "Custom"])
        #expect(Set(state.choices.map(\.symbol)) == ["dumbbell.fill"])
        #expect(state.launchChoice == nil)
    }

    @Test func selectingAndSwitchingModesNeverLaunches() {
        var state = WatchHomeWorkoutSelection()
        for choice in state.choices {
            state.select(choice)
            #expect(state.launchChoice == nil)
        }
        state.show(.cardio)
        // "Personalized Cardio" is phone-only: no Watch destination exists for
        // it yet, so it's deliberately excluded here rather than shown as a
        // dead wheel entry.
        #expect(Set(state.choices) == Set(HomeWorkoutStartChoice.cardioChoices.filter { $0 != .suggestedCardio }))
        #expect(!state.choices.contains(.suggestedCardio))
        for choice in state.choices {
            state.select(choice)
            #expect(state.launchChoice == nil)
        }
        state.show(.strength)
        #expect(state.selection == .strength(.quickStart))
        #expect(state.launchChoice == nil)
    }

    @Test func startSnapshotsSelectionUntilDismissed() {
        var state = WatchHomeWorkoutSelection()
        state.select(.strength(.previous))
        state.start()
        #expect(state.launchChoice == .strength(.previous))
        state.show(.cardio)
        state.select(.cardio(.swim))
        #expect(state.launchChoice == .strength(.previous))
        state.dismissStart()
        #expect(state.launchChoice == nil)
        state.start()
        #expect(state.launchChoice == .cardio(.swim))
    }

    @Test func eachModeRestoresItsOwnChoiceAndAlwaysOpensOnStrength() throws {
        let suite = "WatchHomeWorkoutSelectionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var state = WatchHomeWorkoutSelection.persisted(defaults: defaults)
        state.select(.strength(.previous))
        state.show(.cardio)
        state.select(.cardio(.rowing))
        state.persist(defaults: defaults)
        var restored = WatchHomeWorkoutSelection.persisted(defaults: defaults)
        #expect(restored.mode == .strength)
        #expect(restored.selection == .strength(.previous))
        restored.show(.cardio)
        #expect(restored.selection == .cardio(.rowing))
        #expect(restored.launchChoice == nil)
        #expect(defaults.string(forKey: HomeWorkoutStartChoice.selectionStorageKey) == nil)
    }

    /// D7 (field testing): tapping a row in the instantly-displayed choice
    /// list must pick AND launch it in a single step, not require a separate
    /// Start tap afterward.
    @Test func selectAndStartPicksAndLaunchesInOneStep() {
        var state = WatchHomeWorkoutSelection()
        state.show(.cardio)
        state.selectAndStart(.cardio(.swim))
        #expect(state.selection == .cardio(.swim))
        #expect(state.launchChoice == .cardio(.swim))
    }

    @Test func invalidCrossModeChoicesAndLegacyPreferencesRestoreSafely() {
        var invalid = WatchHomeWorkoutSelection(savedStrengthID: "cardio.swim", savedCardioID: "strength.previous")
        #expect(invalid.selection == .strength(.suggested))
        invalid.select(.cardio(.run))
        #expect(invalid.selection == .strength(.suggested))
        invalid.show(.cardio)
        #expect(invalid.selection == .cardio(.hiit))
        let legacy = WatchHomeWorkoutSelection(legacyChoiceID: "strength.previous")
        #expect(legacy.selection == .strength(.previous))
    }
}
