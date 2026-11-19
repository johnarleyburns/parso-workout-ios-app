import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchStrengthSettingsTests {
    @Test func popularRepPatternsIncludeCommonStrengthAndHypertrophyChoices() {
        let ids = WatchRepPattern.popular.map(\.id)

        #expect(ids.contains("12-10-8"))
        #expect(ids.contains("12-10-8-6"))
        #expect(ids.contains("5-5-5"))
    }

    @Test func repPatternNormalizationFallsBackToDefault() {
        #expect(WatchRepPattern.normalized([]) == .fallback)
        #expect(WatchRepPattern.normalized([12, 10, 8]).id == "12-10-8")
    }

    @Test func restOptionsNormalizeToPopularChoices() {
        #expect(WatchRestOptions.popular == [20, 30, 60, 90])
        #expect(WatchRestOptions.normalized(90) == 90)
        #expect(WatchRestOptions.normalized(45) == 60)
    }

    @Test func customStrengthDefaultsRestoreLastRepRestAndPartners() {
        let defaults = WatchCustomStrengthDefaults(
            storedRepPattern: "5-5-5",
            storedRestSeconds: 90,
            storedPartners: "Sam\nAlex",
            recentPartners: ["Alex", "Jo"]
        )

        #expect(defaults.repPattern.id == "5-5-5")
        #expect(defaults.restSeconds == 90)
        #expect(defaults.selectedPartners == ["Sam", "Alex"])
        #expect(defaults.partnerOptions == ["Sam", "Alex", "Jo"])
    }

    @Test func customStrengthDefaultsPreserveSoloLastWorkout() {
        let defaults = WatchCustomStrengthDefaults(
            storedRepPattern: "12-10-8-6",
            storedRestSeconds: 20,
            storedPartners: "",
            recentPartners: ["Sam"]
        )

        #expect(defaults.repPattern.id == "12-10-8-6")
        #expect(defaults.restSeconds == 20)
        #expect(defaults.selectedPartners == [])
        #expect(defaults.partnerOptions == ["Sam"])
    }

    @Test func exerciseSearchPresenterShowsSpinnerWhileSearchIsOngoing() {
        #expect(
            WatchExerciseSearchPresenter.phase(query: "bench", isSearching: true, resultCount: 0) ==
            .searching
        )
        #expect(
            WatchExerciseSearchPresenter.phase(query: "bench", isSearching: true, resultCount: 3) ==
            .searching,
            "An in-flight query should show progress instead of stale results."
        )
        #expect(
            WatchExerciseSearchPresenter.phase(query: "bench", isSearching: false, resultCount: 0) ==
            .noMatches
        )
    }

    @Test func plateIncrementsUseCommonPoundAndKilogramPlates() {
        let expected = [45.0, 35, 25, 10, 5, 2.5]
        #expect(WeightIncrement(unit: .pounds).plateOptions == expected)
        #expect(WeightIncrement(unit: .kilograms).plateOptions == expected)
        #expect(WeightIncrement(unit: .pounds).crownDetent == 0.1)
    }

    @Test func rirConvertsToStoredRPE() {
        #expect(WatchEffortMode.rir.rpeValue(from: 2) == 8)
        #expect(WatchEffortMode.rpe.rpeValue(from: 9) == 9)
        #expect(WatchEffortMode.rpe.rpeValue(from: nil) == nil)
    }
}
