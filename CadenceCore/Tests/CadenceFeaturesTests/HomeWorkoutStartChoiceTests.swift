import Foundation
import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct HomeWorkoutStartChoiceTests {
    @Test func onlyLiftIsOfferedForStrength() {
        #expect(HomeStrengthStartChoice.allCases.map(\.title) == ["Lift"])
        #expect(HomeWorkoutStartChoice.strengthChoices.map(\.title) == ["Lift"])
        #expect(HomeRecentCardioChoices.recent(["run", "run", "walk", "cycle", "swim"]) ==
                       ["run", "walk", "cycle"])
        #expect(HomeRecentCardioChoices.recent([String]()) == [])
    }
    @Test func unifiedPhoneAndWatchChoicesIncludeEveryWorkoutOnce() {
        let choices = HomeWorkoutStartChoice.allChoices
        #expect(choices.map(\.title) == [
            "Lift", "Personalized Cardio", "HIIT",
            "Run", "Walk", "Cycle", "Rowing", "Swim", "Elliptical", "Stairs", "Boxing", "Custom"
        ])
        #expect(Set(choices.map(\.id)).count == choices.count)
        for type in WorkoutType.allCases where type != .weights {
            #expect(choices.contains(.cardio(type)))
        }
        #expect(!choices.contains(.cardio(.weights)))
        #expect(Set(HomeWorkoutStartChoice.strengthChoices.map(\.symbol)) == ["dumbbell.fill"])
        #expect(choices.allSatisfy { !$0.symbol.isEmpty })
    }

    @Test func personalizedCardioChoiceSuggestsCardioLikeStrengthDoes() {
        #expect(HomeWorkoutStartChoice.cardioChoices.contains(.suggestedCardio))
        #expect(HomeWorkoutStartChoice.suggestedCardio.title == "Personalized Cardio")
        #expect(HomeWorkoutStartChoice.suggestedCardio.id == "cardio.suggested")
    }

    @Test func everyChoiceRestoresFromPersistedSelection() throws {
        let suiteName = "HomeWorkoutStartChoiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = HomeWorkoutStartChoice.selectionStorageKey
        for choice in HomeWorkoutStartChoice.allChoices {
            defaults.set(choice.id, forKey: key)
            let reopened = try #require(UserDefaults(suiteName: suiteName))
            let saved = try #require(reopened.string(forKey: key))
            #expect(HomeWorkoutStartChoice.restored(from: saved) == choice)
        }
    }

    @Test func missingOrRetiredStrengthSelectionUsesLift() {
        for identifier in ["", "cardio.removedActivity", "strength.removedSource",
                           "strength.previous", "strength.quickStart", "cardio.weights"] {
            #expect(HomeWorkoutStartChoice.restored(from: identifier) == .strength(.suggested))
        }
    }

}
