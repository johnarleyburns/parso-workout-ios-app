import Foundation
import Testing
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WeeklyDetailSelectionTests {
    @Test func weeklyDetailsCanBeExpandedIndependently() {
        var selection = WeeklyDetailSelection()

        selection.toggle(.strength)
        #expect(selection.isExpanded(.muscleMap))
        #expect(selection.isExpanded(.strength))

        selection.toggle(.cardio)
        #expect(selection.isExpanded(.cardio))
        #expect(selection.isExpanded(.strength))

        selection.toggle(.muscleMap)
        #expect(!selection.isExpanded(.muscleMap))
        #expect(selection.isExpanded(.muscleGroupVolume) == false)
    }

    @Test func selectingAWeeklyDetailDoesNotCollapseOtherDetails() {
        var selection = WeeklyDetailSelection(expanded: [.muscleGroupVolume])

        selection.select(.cardio)
        #expect(selection.isExpanded(.muscleGroupVolume))
        #expect(selection.isExpanded(.cardio))

        selection.select(.cardio)
        #expect(selection.isExpanded(.cardio))
    }

    @Test func togglingExpandedWeeklyDetailCollapsesOnlyThatDetail() {
        var selection = WeeklyDetailSelection(expanded: [.muscleMap, .strength])

        selection.toggle(.muscleMap)

        #expect(!selection.isExpanded(.muscleMap))
        #expect(selection.isExpanded(.strength))
    }

    @Test func freshSelectionExpandsTheMuscleMapOnly() {
        let selection = WeeklyDetailSelection()

        #expect(selection.isExpanded(.muscleMap))
        #expect(!selection.isExpanded(.muscleGroupVolume))
        #expect(!selection.isExpanded(.strength))
        #expect(!selection.isExpanded(.cardio))
    }

    @Test func persistedSelectionRoundTripsIndependentExpansion() {
        let defaults = InMemoryDefaultsStore()

        let original = WeeklyDetailSelection(expanded: [.muscleGroupVolume, .cardio])
        original.persist(defaults: defaults)

        #expect(WeeklyDetailSelection.persisted(defaults: defaults) == original)
    }

    @Test func ringTapsMapToTheMatchingThisWeekSection() {
        #expect(ThisWeekDestination.forRing(.sets) == .muscleCoverage)
        #expect(ThisWeekDestination.forRing(.cardioMinutes) == .cardio)

        #expect(ThisWeekDestination.muscleCoverage.detailMode == .muscleMap)
        #expect(ThisWeekDestination.strength.detailMode == .strength)
        #expect(ThisWeekDestination.cardio.detailMode == .cardio)
    }

    @Test func thisWeekSectionRequestRoundTripsAndClears() {
        let defaults = InMemoryPlatformDefaultsStore()

        #expect(CadencePlatformRequestStore.consumeThisWeekSection(defaults: defaults) == nil)
        CadencePlatformRequestStore.requestThisWeekSection(.cardio, defaults: defaults)
        #expect(CadencePlatformRequestStore.consumeThisWeekSection(defaults: defaults) == .cardio)
        #expect(CadencePlatformRequestStore.consumeThisWeekSection(defaults: defaults) == nil)
    }

    @Test func persistedSelectionIgnoresUnknownModes() {
        let defaults = InMemoryDefaultsStore()

        defaults.set(["muscleMap", "not-a-real-section"],
                     forKey: WeeklyDetailSelection.persistenceKey)

        #expect(WeeklyDetailSelection.persisted(defaults: defaults).expanded == [.muscleMap])
    }
}
