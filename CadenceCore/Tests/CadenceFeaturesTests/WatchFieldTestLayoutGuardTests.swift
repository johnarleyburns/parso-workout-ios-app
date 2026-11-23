import Foundation
import Testing

/// Structural guards for the Watch field-testing batch. SwiftUI composition
/// cannot be rendered by the headless host suite, so these tests keep the
/// requested controls, titles, back paths and compact spacing in the shipped
/// production views.
struct WatchFieldTestLayoutGuardTests {
    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CadenceFeaturesTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // CadenceCore
            .deletingLastPathComponent() // repo root
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func watch(_ name: String) throws -> String {
        try source("Cadence/Cadence Watch App Watch App/\(name)")
    }

    @Test func homeRowsUseCompactInsetsInsteadOfListDefaultSpacing() throws {
        let root = try watch("WatchRootView.swift")
        #expect(root.contains("WatchCompactHomeList"))
        let rows = try watch("WatchHomeStartControls.swift")
        #expect(rows.contains("defaultMinListRowHeight"))
        #expect(rows.contains(".listRowInsets("))
        #expect(rows.contains("bottom: 1"))
    }

    @Test func liftDoesNotBlankAndReloadOnEveryBodyUpdate() throws {
        let lift = try watch("WatchHomeSuggestedStrengthView.swift")
        #expect(lift.contains("WatchSuggestedStrengthRefreshPolicy"))
        #expect(!lift.contains(".task(id: manager.mesocycleMirrorRevision)"))
    }

    @Test func liftPreviewExposesWhyThisWorkout() throws {
        let preview = try watch("WatchStrengthPreview.swift")
        #expect(preview.contains("WatchLiftWhyPresentation"))
        #expect(preview.contains("WatchLiftWhyView"))
    }

    @Test func warmUpUsesOneBottomToolbarWithPauseSkipAndAddOne() throws {
        let warmUp = try watch("WatchWarmUpView.swift")
        #expect(warmUp.contains(".bottomBar"))
        #expect(warmUp.contains("WatchWarmUpControlPresentation.pauseSystemImage"))
        #expect(warmUp.contains("WatchWarmUpControlPresentation.skipSystemImage"))
        #expect(warmUp.contains("WatchWarmUpControlPresentation.addOneMinuteLabel"))
        #expect(!warmUp.contains("+5 min"))
        #expect(!warmUp.contains("watchWarmup.addFiveMinutes"))
        #expect(!warmUp.contains("Button(\"Skip\")"))
    }

    @Test func setEntryIsTightAndLogsWithAWideCheckbox() throws {
        let set = try watch("WatchSetKeypadView.swift")
        #expect(set.contains("WatchSetEntryPresentation.logButtonSystemImage"))
        #expect(set.contains("WatchSetEntryPresentation.logButtonMinimumWidth"))
        #expect(set.contains("WatchSetEntryPresentation.headerSpacing"))
        #expect(!set.contains("Text(\"Log\")"))
        #expect(!set.contains("lineLimit(2, reservesSpace: true)"))
    }

    @Test func summaryPageIsTitledAndHasNoReservedEmptyRow() throws {
        let pages = try watch("WatchStrengthPages.swift")
        #expect(pages.contains("WatchStrengthControlsPresentation.title"))
        #expect(!pages.contains(".frame(minHeight: 28)"))
        #expect(pages.contains("showingPartners"))
    }

    @Test func exercisePlanHasNoSuggestButton() throws {
        let home = try watch("WatchStrengthHomeView.swift")
        #expect(!home.contains("watchStrength.suggestExercise"))
        #expect(!home.contains("showingSuggestion"))
        #expect(!home.contains("WatchSuggestedExerciseView("))
    }

    @Test func addExerciseIsTitledHasABackPathAndListsTheSuggestion() throws {
        let add = try watch("WatchAddExerciseView.swift")
        #expect(add.contains("WatchAddExerciseSuggestionPresentation.pageTitle"))
        #expect(add.contains("WatchAddExerciseSuggestionPresentation.sectionTitle"))
        #expect(add.contains("WatchBackButton"))
        #expect(add.contains("WatchAddExerciseSuggestionPresentation.rowIdentifierPrefix"))
        #expect(add.contains("WatchExerciseSuggestionGuard"))
    }

    @Test func partnersShowsKnownPartnersAndOffersAWayBack() throws {
        let partners = try watch("WatchPartnersView.swift")
        #expect(partners.contains("WatchPartnerDirectory"))
        #expect(partners.contains("WatchBackButton") || partners.contains("Button(\"Done\")"))
        #expect(!partners.contains("Section(\"Rotation\")"))
        #expect(partners.contains("Section(\"Partners\")"))
    }
}
