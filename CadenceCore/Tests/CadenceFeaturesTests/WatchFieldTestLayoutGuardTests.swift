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
        #expect(rows.contains("bottom: 3"))
        #expect(rows.contains("minHeight: 52"))
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

    @Test func warmUpAndCoolDownShareOneBottomToolbarWithZoneText() throws {
        let phase = try watch("WatchPhaseTimerView.swift")
        #expect(phase.contains(".bottomBar"))
        #expect(phase.contains("WatchHeartRateZoneText.code"))
        #expect(phase.contains(".navigationTitle"))
        #expect(!phase.contains("WARM-UP"))
        #expect(!phase.contains("COOL-DOWN"))

        let warmUp = try watch("WatchWarmUpView.swift")
        #expect(warmUp.contains("WatchPhaseTimerView"))
        #expect(warmUp.contains("WatchPhasePresentation.warmUpTitle"))
        #expect(!warmUp.contains("+5 min"))
        #expect(!warmUp.contains("watchWarmup.addFiveMinutes"))
        #expect(!warmUp.contains("Button(\"Skip\")"))

        let coolDown = try watch("WatchCoolDownView.swift")
        #expect(coolDown.contains("WatchPhaseTimerView"))
        #expect(coolDown.contains("WatchPhasePresentation.coolDownTitle"))
        #expect(coolDown.contains("WatchPhasePresentation.endSystemImage"))
        #expect(!coolDown.contains("+5 min"))
        #expect(!coolDown.contains("watchCooldown.addFiveMinutes"))
    }

    @Test func setEntryIsTightAndLogsWithAnUnboxedCheckbox() throws {
        let set = try watch("WatchSetKeypadView.swift")
        #expect(set.contains("WatchSetEntryPresentation.logButtonSystemImage"))
        #expect(set.contains("String(localized: \"rps\")"))
        #expect(set.contains("WatchSetEntryPresentation.headerSpacing"))
        let components = try watch("WatchKitComponents.swift")
        #expect(components.contains(".font(.system(.title3"))
        #expect(!set.contains(".borderedProminent"))
        #expect(!set.contains("Text(\"Log\")"))
        #expect(!set.contains("lineLimit(2, reservesSpace: true)"))
    }

    @Test func summaryPageIsTitledAndShowsRingsInsteadOfActionTiles() throws {
        let pages = try watch("WatchStrengthPages.swift")
        #expect(pages.contains("WatchStrengthControlsPresentation.title"))
        #expect(pages.contains("WatchLiveSummaryPresentation"))
        #expect(pages.contains(".bottomBar"))
        #expect(pages.contains("WatchStrengthControlsPresentation.finishConfirmationTitle"))
        #expect(pages.contains("WatchPhasePresentation.endSystemImage"))
        #expect(!pages.contains(".frame(minHeight: 28)"))
        #expect(!pages.contains("Water Lock"))
        #expect(!pages.contains("watchStrength.waterLock"))
        #expect(!pages.contains("LazyVGrid"))
        // Workout page: no discarding from inside the workout.
        #expect(!pages.contains("deleteWorkout"))
        #expect(!pages.contains("confirmDiscard"))
    }

    @Test func exercisePlanHasNoSuggestButton() throws {
        let home = try watch("WatchStrengthHomeView.swift")
        #expect(!home.contains("watchStrength.suggestExercise"))
        #expect(!home.contains("showingSuggestion"))
        #expect(!home.contains("WatchSuggestedExerciseView("))
        // Lift scrolling: lazy rows and cached presentations, not a List that
        // recomputes every planned/completed count while scrolling.
        #expect(home.contains("ScrollView"))
        #expect(home.contains("LazyVStack"))
        #expect(home.contains("rowPresentations"))
        #expect(home.contains("refreshRowPresentations()"))
    }

    @Test func restOmitsTheRestingAfterRow() throws {
        let rest = try watch("WatchRestView.swift")
        #expect(!rest.contains("Resting after"))
        #expect(rest.contains("Next ·"))
    }

    @Test func liftPreviewOpensAddExerciseInsteadOfSuggest() throws {
        let preview = try watch("WatchStrengthPreview.swift")
        #expect(preview.contains("WatchPreviewAddExerciseView"))
        #expect(preview.contains("Add exercise"))
        #expect(!preview.contains("Label(\"Suggest\""))
        #expect(!preview.contains("WatchPreviewExerciseSuggestionView"))
    }

    @Test func addExerciseUsesANavTitleBackBarAndSearchFirstList() throws {
        let add = try watch("WatchAddExercisePicker.swift")
        #expect(add.contains("WatchAddExerciseSuggestionPresentation.pageTitle"))
        #expect(add.contains(".navigationTitle"))
        #expect(add.contains("WatchBackButton"))
        #expect(add.contains("WatchAddExerciseSuggestionPresentation.customRowTitle"))
        #expect(add.contains("WatchAddExerciseSuggestionPresentation.rowIdentifierPrefix"))
        #expect(add.contains("WatchExerciseSuggestionGuard"))
        #expect(add.contains("queryIsEmpty"))
        #expect(!add.contains("watchAddExercise.cancel"))
        #expect(add.contains("TextField(\"Search\""))
        #expect(add.contains(".frame(maxWidth: .infinity, minHeight: 44)"))
        #expect(!add.contains("customExerciseButton"))
    }

    @Test func addExerciseSearchPrecomputesRowsOffTheMainThread() throws {
        let add = try watch("WatchAddExercisePicker.swift")
        #expect(add.contains("Task.detached"))
        #expect(add.contains("WatchAddExerciseSearchRow"))
        #expect(add.contains("displayName: $0.name.localizedExerciseName"))
    }

    @Test func partnersShowsKnownPartnersAndOffersAWayBack() throws {
        let partners = try watch("WatchPartnersView.swift")
        #expect(partners.contains("WatchPartnerDirectory"))
        #expect(partners.contains("WatchBackButton") || partners.contains("Button(\"Done\")"))
        #expect(!partners.contains("Section(\"Rotation\")"))
        #expect(partners.contains("Section(\"Partners\")"))
    }
}
