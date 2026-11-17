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
