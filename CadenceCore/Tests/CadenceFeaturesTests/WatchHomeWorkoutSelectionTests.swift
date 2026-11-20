import Foundation
import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchHomeWorkoutSelectionTests {
    @Test func defaultsToThePhoneDefaultAndOffersEveryPhoneChoiceInOrder() {
        let state = WatchHomeWorkoutSelection()
        #expect(state.choice == HomeWorkoutStartChoice.defaultChoice)
        #expect(state.choices.map(\.id) == HomeWorkoutStartChoice.allChoices.map(\.id))
        #expect(state.choices.map(\.title) == HomeWorkoutStartChoice.allChoices.map(\.title))
        #expect(state.choices.contains(.suggestedCardio))
        #expect(state.launchChoice == nil)
    }

    @Test func selectingAnyChoiceOnlyStoresItAndNeverLaunches() {
        var state = WatchHomeWorkoutSelection()
        for choice in state.choices {
            state.select(choice)
            #expect(state.choice == choice)
            #expect(state.launchChoice == nil)
        }
    }

    @Test func selectAndStartPicksAndLaunchesInOneStep() {
        var state = WatchHomeWorkoutSelection()
        state.selectAndStart(.cardio(.swim))
        #expect(state.choice == .cardio(.swim))
        #expect(state.launchChoice == .cardio(.swim))
    }

    @Test func startSnapshotsTheSelectionUntilDismissed() {
        var state = WatchHomeWorkoutSelection()
        state.select(.strength(.suggested))
        state.start()
        #expect(state.launchChoice == .strength(.suggested))
        state.select(.cardio(.swim))
        #expect(state.launchChoice == .strength(.suggested))
        state.dismissStart()
        #expect(state.launchChoice == nil)
        state.start()
        #expect(state.launchChoice == .cardio(.swim))
    }

    @Test func persistedChoiceRoundTripsAndLegacyPerModeKeysStillRestore() throws {
        let defaults = InMemoryDefaultsStore()

        var state = WatchHomeWorkoutSelection.persisted(defaults: defaults)
        state.select(.cardio(.rowing))
        state.persist(defaults: defaults)
        let restored = WatchHomeWorkoutSelection.persisted(defaults: defaults)
        #expect(restored.choice == .cardio(.rowing))
        #expect(restored.launchChoice == nil)

        defaults.removeObject(forKey: WatchHomeWorkoutSelection.storageKey)
        defaults.set("strength.previous", forKey: WatchHomeWorkoutSelection.legacyStrengthStorageKey)
        defaults.removeObject(forKey: WatchHomeWorkoutSelection.legacyCardioStorageKey)
        #expect(WatchHomeWorkoutSelection.persisted(defaults: defaults).choice == .strength(.suggested))

        defaults.removeObject(forKey: WatchHomeWorkoutSelection.legacyStrengthStorageKey)
        defaults.set("cardio.swim", forKey: WatchHomeWorkoutSelection.legacyCardioStorageKey)
        #expect(WatchHomeWorkoutSelection.persisted(defaults: defaults).choice == .cardio(.swim))
    }

    @Test func invalidSavedIdentifiersFallBackSafely() {
        let invalid = WatchHomeWorkoutSelection(savedID: "cardio.not-real")
        #expect(invalid.choice == HomeWorkoutStartChoice.defaultChoice)
        let legacy = WatchHomeWorkoutSelection(legacyChoiceID: "strength.previous")
        #expect(legacy.choice == .strength(.suggested))
    }
}
