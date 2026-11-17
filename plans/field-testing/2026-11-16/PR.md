# Fix Workout home, plan controls, activity colors, and Watch bodyweight entry

Local PR draft on `fix/field-testing-workout-polish`. No branch push or GitHub PR
publication is authorized. Base is local commit `944e3e38` from
`fix/unified-workout-home`; retain that dependency when publishing.

Workout home now keeps the picker and Start Workout above the tab bar, adds
space below the title, and opens standalone history from its upper-left icon.
History leaves the Progress picker; its Archive and Share icons retain restore
and export functionality. Strength choices are Optimal Lifts, Repeat Lifts, and
Quick Start, all with the same lifting icon. The redundant Repeat shortcut is
removed. Start and Connect HR controls stop stacking a minimum label height
with system button padding; Start uses a darker green for white-text contrast.

Workout Plan has an upper-left close icon, an edit/preview icon, and no Done,
bottom Cancel/Done, or Suggest Another controls. Repeat Lifts presents its plan
as a dismissible sheet. A rep-structure control for each performer applies the
chosen structure to all exercises while retaining that person's exercise loads
and leaving other performers unchanged. Owner changes also update the owner's
mirrored performer prescription.

Phone and Watch weekly rings share distinct strength/cardio RGB palettes in
all four existing red/yellow/light-green/green bands. Thresholds are unchanged.
Mountain Climbers use BW on the Watch set card, disable load controls including
Crown/exact entry, and normalize saved sets to zero external load with the
bodyweight flag. Other non-weighted movements retain their existing label.

## Requirement → production entry → regression / device check

| Requirement | Production entry | Automated coverage / device check |
| --- | --- | --- |
| Title margin, bottom start controls, remove Repeat | HomeView+DashboardScroll / DashboardContent | Rendered device checks 1–2 |
| History entry and Archive/Share icons | HomeView+DashboardScroll / HistoryView | Device check 3 |
| Remove history from Progress, restore old selection safely | ProgressQuestionSelection / TrainingProgressView | ProgressQuestionSelectionTests; check 3 |
| Strength picker names and lifting icons, stable saved selection | HomeWorkoutStartChoice / HomeWorkoutStartControls | HomeWorkoutStartChoiceTests; check 2 |
| Standard height and legible Start, compact HR buttons | HomeWorkoutStartControls / PreWorkoutHRView | Rendered device checks 2, 4 |
| Dismissible plan with X, remove redundant actions | WorkoutPlanEditor / HomePreviousStrengthWorkouts | Rendered device check 5 |
| Rep structures for each partner across all exercises | WorkoutPlanEditor+RepStructure → EditablePlan.applyRepStructure → performerPrescriptions | WorkoutPlanRepStructureTests; check 6 |
| Distinguishable activity colors on both devices | WeeklyActivityPalette → WeeklyIntentRingsCard / WatchWeekView | WeeklyActivityColorTests; check 7 |
| BW Mountain Climbers, no load input or saved load | WatchSetCard / WatchSetKeypadView → WatchStrengthFlowModel.logSet → normalizedSetEntry | WorkoutPlanRepStructureTests, WatchStrengthFlowModelTests; check 8 |

## Validation

- PASS: Swift frontend syntax parsing of all 26 changed/new Swift files.
- PASS: test-pyramid, design-token, history-safety, Watch handler-isolation guardrails.
- PASS: `git diff --check`.
- BLOCKED: `swift test --package-path CadenceCore --parallel --filter HomeWorkoutStartChoiceTests`
  fails before running tests: Linux lacks Apple's SwiftData module. The changed
  expectation was written before production changes, but failing→passing test
  execution cannot be established here. Additional regressions are saved for Mac.
- Xcode generic iPhone/Watch builds and full package suite require a Mac. Xcode is
  absent in this workspace. No simulator was launched.
- UI rendering, glass height, actual color distinguishability, and touch/Crown
  behavior require devices; syntax checks do not verify them.

Before publication, run `swift test --package-path CadenceCore --parallel` and
sequential generic iOS and watchOS destination builds on a Mac. Review the device
checklist before merging. No TestFlight binary has been produced; exact version
and build must be recorded by the release owner when available.

## Device verification (owner: app maintainer; pending)

Record device, OS, exact TestFlight version/build, and pass/fail per item.

1. Open Workout on a small iPhone and with accessibility text. Confirm space
   below the title and that all content remains reachable.
2. Confirm picker/Start sit above the tab bar with margin, including after
   scrolling. Compare Start height with plan buttons and check white text on
   dark green in light/dark mode. Confirm no Repeat text below it. Verify the
   three lifting names/icons, all cardio choices, and saved selection reopening.
3. Tap upper-left History. Open strength/cardio details and return. Tap Archive,
   restore a deleted workout, return to active history, then Share and export.
   Confirm Progress has no history option, including with an old saved history
   selection; charts, observations, and tests must remain available.
4. Start a workout through Connect HR. Compare Continue/Cancel with standard
   plan buttons; verify strap/Watch connection, continue, and cancellation.
5. Open Optimal Lifts, Repeat Lifts, and Quick Start plan sheets. Verify X and
   swipe dismissal, edit/preview, Start, no Suggest Another, no Done or bottom
   Cancel. Verify closing a generated plan clears its preview state.
6. Include Me and two partners with two different exercises/loads. Apply a
   different rep structure to each person. Verify every exercise changes only
   for that person; preview then start and verify actual set targets and loads
   on phone and Watch. Check adding sets repeats the selected person's last load.
7. Compare strength/cardio weekly rings on phone and Watch at zero, below
   minimum, between limits, and above upper limit. Confirm red/yellow/light
   green/green remain recognizable and the two activities distinguishable in
   each band. Check light/dark and reduced luminance on Watch.
8. On Watch start Mountain Climbers, including from history with a stale load.
   Verify BW instead of 0 lbs/kg; no weight +/- or exact entry; Crown changes
   reps. Log a set, complete/sync, and confirm zero external load/bodyweight in
   history. Repeat with a partner and verify normal weighted lifts remain editable.

## Completion audit

All requested areas map to saved production changes above. No schema migration,
push, auto-merge, deployment, or remote PR creation was performed. Functional
acceptance remains pending Mac builds/tests and the explicit device checks.

## Watch follow-ups included in this local PR

The home wheel is one 44-point row with strength-only Personalized, Previous,
and Custom choices (each uses the lifting icon). The newer terminology request
supersedes the initial Suggested label. A native bottom toolbar switches between
strength and all cardio types, restoring a separate saved selection per mode;
opening the launcher defaults to strength. Changing the wheel or modes only
changes the draft selection. Only the native prominent Start button snapshots
and opens a destination. Destinations and toolbar are registered outside lazy
List rows, removing the previous row-wide NavigationLink activation path.

All three strength sources now share `WatchStrengthPreview`: rep-default,
partner and optional rest controls before a native prominent “Start” action.
Personalized/Previous drafts retain original prescriptions until explicitly
changed. A selected rep structure replaces every exercise's reps while keeping
loads; custom workouts attach that structure to exercises added after Start.
Partner selection is passed into the real `WatchStrengthFlowModel.start` path.
An unchanged synced roster retains its phone identities; an explicitly edited
Watch roster resolves the chosen names against Watch-local People on Start.
Original historical workouts remain untouched.

The primary buttons use Apple's `borderedProminent` capsule styling and the
bottom mode controls use `ToolbarItemGroup(placement: .bottomBar)`, following
[Apple's watchOS guidance](https://developer.apple.com/documentation/watchOS-Apps/creating-an-intuitive-and-effective-ui-in-watchos-10).

User-visible workout naming is now Personalized across phone/Watch headings,
loading/error messages, and accessibility strings. Existing translated catalog
entries were updated and marked for translation review; internal enum cases,
storage/transport keys, and accessibility identifiers remain stable.

### Exact last-set defaults investigation

The shared planner and phone `SessionView+State` / `SessionRenderModel` already
use `lastPriorWorkingSet`. Watch-local history and `WatchSetDefaultSnapshot.history`
never populated it. An older 250 lb × 6 followed by 205 lb × 8 therefore reopened
at 250 × 6 through the historical rep-pattern/weight-match fallbacks. Both Watch
inputs now supply the actual last working set, producing 205 × 8 without plate
rounding or estimated progression. Explicit authored targets and today's entered
weights still override history. The phone path required no production change;
a regression checks its existing exact-repeat behavior using the same fixture.

### Follow-up regression map

- `WatchHomeWorkoutSelectionTests`: strength default, all cardio choices, passive
  selection/mode changes, explicit Start snapshot, independent persistence,
  legacy preference recovery. Used directly by the Watch root and controls.
- `WatchStrengthPreviewSetupTests`: original plan preservation, applying reps to
  every prescription with exact loads, roster edits, custom exercise defaults,
  and real model startup with partners/reps.
- `ExerciseRepeatDefaultsTests`: real Watch model startup from local and injected
  synced history; phone render-model parity for 205 lb × 8 after 250 lb × 6.
- `WatchSetDefaultSnapshotTests`: phone→Watch adapter carries exact last set.
- `PerformerSetPlannerLastWorkingSetTests` (existing): explicit plan precedence,
  partner isolation, and history fallback.
- The single Watch UI flow now changes strength/cardio selections without
  starting, checks each mode's remembered value, then configures Custom preview
  rep defaults and a partner before Start. It was extended, not executed here.

### Additional device checks (pending; maintainer records device/OS/build)

9. On the Watch home screen, verify one-row wheel and one-row native primary
   Start with bottom-left lifting and bottom-right cardio controls on small and
   large Watches. Turn the Crown, tap each strength choice, switch modes and
   scroll every cardio choice: no navigation, workout creation or HR session
   before Start. Toggle modes twice, relaunch, and verify separate saved choices
   and strength-first opening. Existing unfinished sessions must still resume.
10. Start Personalized, select a Previous workout, and open Custom. In every
    preview, change rep defaults, choose/add/remove partners, and confirm only
    “Start” creates a session. Verify all exercise reps and partner rotation in
    actual set entry; test Custom exercises added after startup. Go back without
    Start and confirm no workout was created. Check source history unchanged.
11. Verify Personalized wording in phone and Watch strength/cardio headings,
    loading/errors, and VoiceOver. Review updated translations in shipped locales.
12. Log Back Squat at 250 lb × 6 followed by 205 lb × 8, complete it, and open a
    fresh unprescribed session. Confirm 205 × 8 on phone and Watch, including an
    offline Watch after phone-history sync. Repeat with a separate partner and
    warm-up sets. Explicitly choose different preview reps and confirm that
    choice is respected without inventing a heavier load.

The same no-push constraint remains in effect. No remote PR, TestFlight build,
or device acceptance result has been produced.

### Follow-up validation evidence

- PASS: 38 isolated Swift package tests covering the production launcher state,
  preview preparation, full shared set planner and phone→Watch snapshot adapter.
  The temporary package uses verbatim production source and extracted Foundation
  declarations for model values to avoid SwiftData. It excludes real SwiftData
  startup/render-model tests and SwiftUI rendering; it is not a full app build.
- Reproduced failure before repair: the new snapshot regression against the old
  production adapter resolves 6 reps and 113.3980925 kg (250 lb) instead of 8 reps
  and 92.98643585 kg (205 lb). The same regression passes after supplying the
  literal last working set. The launcher naming regression also failed against
  the old Suggested title and passed with Personalized.
- Added optional set timestamps to the history payload, with a legacy-decoding
  test, so newer Watch-local sets beat stale phone history even if the snapshot
  itself was generated more recently. No SwiftData schema changes are involved.
- PASS: changed Swift syntax, JSON catalog parsing, `git diff --check`, test
  pyramid, design tokens, history safety and Watch handler-isolation checks.
- Localization coverage currently fails on existing missing translations and an
  existing plural rule. Comparing the current guard output with HEAD's catalogs
  found zero added failures. Updated translations remain marked for review.
- Full repository SwiftData tests, generic Apple builds, the extended Watch UI
  flow, phone/Watch hardware rendering, and device acceptance remain pending on a
  Mac. No simulator was launched and nothing was pushed.

## Second follow-up: Watch Set Card simplification + Suggest fix

Nine more field-testing items on the same Set Card and its Plan page, same
no-push local PR.

The inline "−5 / … / +5" row is gone. "…" moved to the top-left toolbar and
now opens RPE entry directly — the former "More" screen (Warm-up set, Adjust
weight, Adjust reps, Exact value, This workout, Log as last set, Remove
exercise) is deleted outright, not just hidden; RPE was the only thing left
in it. − and + now live in the bottom toolbar as plain icons, stepping the
focused value by the same amount as before. The Crown's weight step is a
fixed 0.5 (either unit) instead of a customizable 5 lb/2.5 kg plate jump, so
small/decimal corrections are reachable without a separate exact-entry sheet.
The Log Set button's text is now always "Log set" — it no longer echoes the
entered values or flags "Last set"/"Last set for you". The Plan page (the
exercise list swiped to from the Set Card) is titled plainly "Exercises"
instead of the started workout's name, and its "Suggest exercise" row is now
"Suggest".

**Capability changes, not just relabeling:** removing the old More screen
drops the ability to delete one already-logged set from the Watch mid-workout
(the old "This workout" section) — no replacement exists after this change.
Removing an exercise is still possible, but only via the long-press gesture
already on the Plan page row (pre-existing, unrelated to this change); the
duplicate "Remove exercise" entry that lived in More is gone.

**"Suggest" never resolving:** `WatchSuggestedExerciseShellTests.swift` had
one test for a *missing* phone context (`.unavailable`) and none for the
happy path. Added
`testRealisticContextResolvesPastCalculatingInsteadOfHangingForever`, built
from the same realistic context shape `WatchSingleExerciseSuggestionAssemblerTests`
already proves the assembler accepts. Could not execute it here: everything
that imports `SuggestedWorkoutGenerator.swift` — including this new test and
the pre-existing `WatchSingleExerciseSuggestionSessionTests` that already use
the real generator — fails to build on Linux for a reason unrelated to
SwiftData: `String(localized:bundle:)` does not exist in swift-corelibs-
Foundation on this toolchain (confirmed with a two-line repro script, not
just inferred from a build log). Reading `WatchSuggestedExerciseShell` →
`WatchSingleExerciseSuggestionSession` → `WatchSingleExerciseSuggestionAssembler`
→ `WatchSingleExerciseSuggestionContext` end to end found no defect — each
stage is already covered and passes elsewhere (the session resolves
correctly with the real generator in `testInitialResultMatchesSharedGenerator`;
the assembler accepts a realistic context in
`WatchSingleExerciseSuggestionAssemblerTests`). I did not ship a speculative
fix for a defect I could not locate or reproduce. If this still hangs on a
device after a Mac test run of the new regression passes, the next step is a
device trace of `shell.phase`/`session.state` transitions, since nothing in
the engine chain explains a permanent hang from here.

| Requirement | Production entry | Automated coverage / device check |
| --- | --- | --- |
| Remove inline −5/…/+5 row; "…" to top-left toolbar; − / + to bottom toolbar | `WatchSetKeypadView` toolbar | Rendered device check 13 |
| Log Set text always reads "Log set" | `WatchSetCardBuilder.make` → `WatchSetKeypadView.logButton` | `WatchRedesignTests.testLogTitleAlwaysReadsLogSetEvenWhenTheSetEchoesAChange`, `WatchStrengthFlowModelTests.testSetCardNextLifterSkipsCompleted`; check 13 |
| Delete the More screen; "…" opens RPE directly | `WatchSetKeypadView` → `WatchRPEPickerSheet` | Extended single Watch XCUITest flow; check 14 |
| Crown: no plate snap, 0.5 lock, true decimal | `WatchSetCardMetricLayout.crownStep`/`weightStep` | `WatchSetCardMetricTextTests.weightCrownLocksToAHalfUnitDecimalStepNotAPlateJump`; check 15 |
| Plan page titled "Exercises"; "Suggest" rename | `WatchStrengthHomeView.planList` | Extended single Watch XCUITest flow; check 13 |
| "Suggest" resolves instead of hanging forever | `WatchSuggestedExerciseShell.calculate` → `WatchSingleExerciseSuggestionSession` | `WatchSuggestedExerciseShellTests.testRealisticContextResolvesPastCalculatingInsteadOfHangingForever` (Mac-only, see above); check 16 |

### Validation

- PASS: `swiftc -parse` on all 8 changed-and-still-present Swift files (the
  other 5 touched files were deletions).
- PASS: 5 isolated Swift package tests on Linux (a scratch package containing
  only `WatchSetCardMetricLayout.swift` + `WatchRPESelection.swift`, which use
  no `bundle: .module` strings and no SwiftData) — the crown step is 0.5 for
  weight/1 for reps, and `WatchRPESelection.apply` is unchanged by this PR.
- BLOCKED on Linux, same as before: everything touching `WatchSetCard.swift`
  (uses `bundle: .module`) or `SuggestedWorkoutGenerator.swift` (uses
  `String(localized:bundle:)`, absent from swift-corelibs-Foundation) needs a
  Mac. This includes the new/edited tests in `WatchRedesignTests.swift`,
  `WatchStrengthFlowModelTests.swift`, and `WatchSuggestedExerciseShellTests.swift`.
- PASS: test-pyramid, design-token, history-safety, Watch handler-isolation
  guardrails; `git diff --check`.
- Localization coverage guard output is byte-identical before/after this
  commit (diffed directly) — zero new catalog-side failures. This is because
  the guard only validates keys already present in the `.xcstrings` files; the
  two new source strings ("Exercises", "Suggest") aren't registered there yet
  and need the same Mac-only `scripts/sync-localization-catalogs.sh` pass the
  rest of this branch's new strings are waiting on.
- Deleted five now-dead files (and their tests) whose only callers were the
  removed More screen: `WatchSetEntryViews.swift` (`WatchNumericEntrySheet`,
  `WatchWeightAdjustSection`, `WatchRepsAdjustSection`), `WatchSetEntryParser.swift`,
  `WatchNumericEntry.swift`, `WatchSetCardAdjustmentLayout.swift`. Also removed
  `WatchRPESelection.rowText`/`.coachGuidance` and `WatchSetDetailsSection`
  (dead once the RPE sheet is reached directly). Confirmed via repo-wide grep
  that nothing else referenced any of them before deleting.
- The single allowed Watch XCUITest was extended in place (no new `func`):
  swapped the plate-picker/"This workout"-delete/Remove-exercise-via-More
  assertions for the new toolbar + direct-RPE-sheet flow and a long-press
  removal on the Plan page; added assertions for the "Exercises" title and
  "Suggest" label.

### Device verification (owner: app maintainer; pending)

13. Open a strength Set Card. Confirm no "−5 / … / +5" row; "…" sits top-left,
    − and + sit bottom-left/bottom-right as plain icons. Turn the Crown through
    a decimal value (e.g. 135.5) and confirm it lands exactly there, not
    rounded to a 5 lb/2.5 kg step. Log a set with changed weight/reps and with
    the last planned set — in both cases the button still reads "Log set".
    Swipe to the Plan page and confirm its title reads "Exercises" (not the
    workout's name) and its suggestion row reads "Suggest".
14. Tap "…" and confirm it opens RPE entry directly (no intermediate list, no
    "Set Details" title). Pick an RPE and confirm it's applied and the sheet
    closes; reopen and swipe down to cancel without changing anything. Confirm
    there is no way to delete a single already-logged set from the Watch, and
    that removing the current exercise is reachable only via long-press on the
    Plan page row.
15. On Mountain Climbers (or another non-weighted movement), confirm the
    Crown's step is unaffected (still reps-only) and the bottom-bar − / +
    still adjust reps, never weight.
16. Start a workout, add an exercise, tap "Suggest", and confirm it resolves
    to a candidate (or a clear "no result"/"needs sync" message) rather than
    showing "Finding an exercise…" indefinitely. If it still hangs, capture a
    device log of the Watch app around that moment — the production code path
    does not explain a permanent hang on its own.

The same no-push constraint remains in effect through this section too.
