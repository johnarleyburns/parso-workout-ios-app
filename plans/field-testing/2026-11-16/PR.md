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
