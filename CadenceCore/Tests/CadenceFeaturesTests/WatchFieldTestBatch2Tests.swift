import Testing
import CadenceCore
@testable import CadenceWorkoutFeatures

/// Headless behavior for the second Watch field-test batch: HR zone text,
/// live Summary rings, warm-up/cool-down chrome, the set-entry abbreviation,
/// and the Add Exercise custom row.
struct WatchFieldTestBatch2Tests {
    @Test func heartRateZoneCodeFollowsTheSharedZoneBands() {
        #expect(WatchHeartRateZoneText.code(bpm: nil, maxHR: 200) == nil)
        #expect(WatchHeartRateZoneText.code(bpm: 100, maxHR: 200) == "Z1")
        #expect(WatchHeartRateZoneText.code(bpm: 130, maxHR: 200) == "Z2")
        #expect(WatchHeartRateZoneText.code(bpm: 150, maxHR: 200) == "Z3")
        #expect(WatchHeartRateZoneText.code(bpm: 170, maxHR: 200) == "Z4")
        #expect(WatchHeartRateZoneText.code(bpm: 190, maxHR: 200) == "Z5")
        #expect(WatchHeartRateZoneText.code(bpm: 150, maxHR: 0) == nil)
    }

    @Test func liveSummaryReportsSetsAndCardioCompleted() {
        let summary = WatchLiveSummaryPresentation.make(
            setsCompleted: 6, setsPlanned: 12, cardioMinutes: 15)
        #expect(summary.setsCompleted == 6)
        #expect(summary.setsPlanned == 12)
        #expect(summary.cardioMinutes == 15)
        #expect(abs(summary.setsProgress - 0.5) < 1e-9)
        #expect(abs(summary.cardioProgress - 0.5) < 1e-9)
    }

    @Test func liveSummaryNeverDividesByZeroAndClampsProgress() {
        let empty = WatchLiveSummaryPresentation.make(
            setsCompleted: 0, setsPlanned: 0, cardioMinutes: 0)
        #expect(empty.setsProgress == 0)
        #expect(empty.cardioProgress == 0)

        let over = WatchLiveSummaryPresentation.make(
            setsCompleted: 20, setsPlanned: 10, cardioMinutes: 90)
        #expect(over.setsProgress == 1)
        #expect(over.cardioProgress == 1)
    }

    @Test func phaseScreensUseTheRequestedTitlesAndEndGlyph() {
        #expect(WatchPhasePresentation.warmUpTitle == "Warm-up")
        #expect(WatchPhasePresentation.coolDownTitle == "Cool Down")
        #expect(WatchPhasePresentation.endSystemImage == "xmark")
        #expect(WatchWarmUpControlPresentation.skipSystemImage == "chevron.forward.2")
    }

    @Test func setEntryUsesTheRequestedAbbreviations() {
        #expect(WatchSetEntryPresentation.repsUnit == "rps")
        #expect(WatchSetEntryPresentation.logButtonSystemImage == "checkmark.square.fill")
    }

    @Test func addExerciseCustomRowHasStableCopy() {
        #expect(WatchAddExerciseSuggestionPresentation.customRowTitle == "Add Custom")
        #expect(WatchAddExerciseSuggestionPresentation.pageTitle == "Add Exercise")
    }

    @Test func endWorkoutDialogCopyIsStable() {
        #expect(WatchStrengthControlsPresentation.title == "Summary")
        #expect(WatchStrengthControlsPresentation.finishConfirmationTitle == "End Workout?")
        #expect(WatchStrengthControlsPresentation.finishCoolDownTitle == "Cool Down")
        #expect(WatchStrengthControlsPresentation.finishCancelTitle == "Cancel")
    }
}
