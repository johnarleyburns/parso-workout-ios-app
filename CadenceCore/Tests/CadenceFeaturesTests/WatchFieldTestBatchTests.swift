import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore

/// Field-testing batch: home density, Lift refresh stability, the missing
/// "Why this workout", duplicate suggestions, warm-up controls, set-entry
/// spacing, the Add Exercise suggested row, the Summary page, and partner
/// back navigation.
struct WatchFieldTestBatchTests {
    // MARK: - Home / Lift refresh

    @Test func firstAppearanceAlwaysBuildsTheLift() {
        #expect(WatchSuggestedStrengthRefreshPolicy.shouldGenerate(
            lastRevision: nil, currentRevision: "r1", hasLaunch: false))
    }

    @Test func repeatedBodyUpdatesDoNotRegenerateAnAlreadyVisibleLift() {
        #expect(!WatchSuggestedStrengthRefreshPolicy.shouldGenerate(
            lastRevision: "r1", currentRevision: "r1", hasLaunch: true))
    }

    @Test func aNewMirrorRevisionRefreshesTheLift() {
        #expect(WatchSuggestedStrengthRefreshPolicy.shouldGenerate(
            lastRevision: "r1", currentRevision: "r2", hasLaunch: true))
    }

    // MARK: - Why this workout

    @Test func whyThisWorkoutIsAbsentWhenTheLaunchHasNoRationale() {
        #expect(WatchLiftWhyPresentation(rationale: nil) == nil)
    }

    @Test func whyThisWorkoutCarriesTheWorkoutAndExerciseReasons() throws {
        let rationale = SuggestedWorkoutRationale(
            whyWorkout: "Chest is below this week's target.",
            exercises: [
                SuggestedExerciseRationale(exerciseName: "Bench Press",
                                           whyExercise: "It trains chest directly.",
                                           whySetRep: "Three sets at 8–12 reps.")
            ])
        let presentation = try #require(WatchLiftWhyPresentation(rationale: rationale))
        #expect(presentation.title == "Why this workout")
        #expect(presentation.whyWorkout == "Chest is below this week's target.")
        #expect(presentation.exercises.map(\.exerciseName) == ["Bench Press"])
        #expect(presentation.exercises.first?.whyExercise == "It trains chest directly.")
        #expect(presentation.exercises.first?.whySetRep == "Three sets at 8–12 reps.")
    }

    @Test func aLaunchKeepsTheRationaleForThePreview() {
        let rationale = SuggestedWorkoutRationale(whyWorkout: "Recovery is low.", exercises: [])
        let launch = WatchLiftLaunch(title: "Lift", exerciseNames: ["Squat"], repLadder: [8],
                                     rationale: rationale)
        #expect(launch.rationale == rationale)
    }

    // MARK: - Suggestions never repeat an exercise already in the workout

    @Test func suggestionGuardMatchesCaseAndPunctuationVariants() {
        #expect(WatchExerciseSuggestionGuard.isAlreadyInWorkout(
            "bench press", activeNames: ["Bench Press"]))
        #expect(WatchExerciseSuggestionGuard.isAlreadyInWorkout(
            "Bench-Press", activeNames: ["bench press"]))
        #expect(!WatchExerciseSuggestionGuard.isAlreadyInWorkout(
            "Barbell Row", activeNames: ["Bench Press"]))
    }

    @Test func addExerciseSuggestedSectionHasStableCopy() {
        #expect(WatchAddExerciseSuggestionPresentation.sectionTitle == "Suggested")
        #expect(WatchAddExerciseSuggestionPresentation.pageTitle == "Add Exercise")
        #expect(WatchAddExerciseSuggestionPresentation.rowAccessibilityHint == "Add exercise")
    }

    // MARK: - Warm-up toolbar

    @Test func warmUpToolbarUsesTheRequestedGlyphs() {
        #expect(WatchWarmUpControlPresentation.pauseSystemImage(isPaused: false) == "pause.fill")
        #expect(WatchWarmUpControlPresentation.pauseSystemImage(isPaused: true) == "play.fill")
        #expect(WatchWarmUpControlPresentation.skipSystemImage == "chevron.forward.2")
        #expect(WatchWarmUpControlPresentation.addOneMinuteLabel == "+1")
    }

    // MARK: - Set entry / Summary / partners

    @Test func setEntryLogControlIsAnUnboxedGreenCheckbox() {
        #expect(WatchSetEntryPresentation.logButtonSystemImage == "checkmark.square.fill")
        #expect(WatchSetEntryPresentation.repsUnit == "rps")
        #expect(WatchSetEntryPresentation.headerSpacing <= 3)
    }

    @Test func summaryPageIsTitledAndUsesOnlyASmallPauseMargin() {
        #expect(WatchStrengthControlsPresentation.title == "Summary")
        #expect(WatchStrengthControlsPresentation.pauseReasonTopPadding <= 4)
    }

    @Test func partnerDirectoryOffersKnownPeopleThatAreNotAlreadyInTheRoster() {
        let addable = WatchPartnerDirectory.addable(
            allNames: ["Alex", "Bailey", "Casey", "alex"],
            currentNames: ["Bailey"])
        #expect(addable == ["Alex", "Casey"])
    }
}
