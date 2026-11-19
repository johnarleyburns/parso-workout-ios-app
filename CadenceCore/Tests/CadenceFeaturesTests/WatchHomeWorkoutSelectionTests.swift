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

    @Test func startSnapshotsTheSelectionUntilDismissed() {
        var state = WatchHomeWorkoutSelection()
        state.select(.strength(.previous))
        state.start()
        #expect(state.launchChoice == .strength(.previous))
        state.select(.cardio(.swim))
        #expect(state.launchChoice == .strength(.previous))
        state.dismissStart()
        #expect(state.launchChoice == nil)
        state.start()
        #expect(state.launchChoice == .cardio(.swim))
    }

    @Test func persistedChoiceRoundTripsAndLegacyPerModeKeysStillRestore() throws {
        let suite = "WatchHomeWorkoutSelectionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var state = WatchHomeWorkoutSelection.persisted(defaults: defaults)
        state.select(.cardio(.rowing))
        state.persist(defaults: defaults)
        let restored = WatchHomeWorkoutSelection.persisted(defaults: defaults)
        #expect(restored.choice == .cardio(.rowing))
        #expect(restored.launchChoice == nil)

        defaults.removeObject(forKey: WatchHomeWorkoutSelection.storageKey)
        defaults.set("strength.previous", forKey: WatchHomeWorkoutSelection.legacyStrengthStorageKey)
        defaults.removeObject(forKey: WatchHomeWorkoutSelection.legacyCardioStorageKey)
        #expect(WatchHomeWorkoutSelection.persisted(defaults: defaults).choice == .strength(.previous))

        defaults.removeObject(forKey: WatchHomeWorkoutSelection.legacyStrengthStorageKey)
        defaults.set("cardio.swim", forKey: WatchHomeWorkoutSelection.legacyCardioStorageKey)
        #expect(WatchHomeWorkoutSelection.persisted(defaults: defaults).choice == .cardio(.swim))
    }

    @Test func invalidSavedIdentifiersFallBackSafely() {
        let invalid = WatchHomeWorkoutSelection(savedID: "cardio.not-real")
        #expect(invalid.choice == HomeWorkoutStartChoice.defaultChoice)
        let legacy = WatchHomeWorkoutSelection(legacyChoiceID: "strength.previous")
        #expect(legacy.choice == .strength(.previous))
    }
}
