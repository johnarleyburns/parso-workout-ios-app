# fix: weekly totals, Watch launcher and workout-plan/history follow-ups

Prepared locally on `fix/workout-review-followups`, based on `c8e46f05` (merged #776). Publication authorized by the owner. Apple-platform validation runs in PR CI; auto-merge waits for required checks, then the main-branch release workflow builds for TestFlight.

Phone weekly totals now have a “Totals this week” heading and 200-point rings (previously 104). Suggested plans open in preview, fill missing owner targets from the literal last working set, and retain their suggested set count and explicit loads. Rep-structure buttons include the current ladder and the sheet marks the selected structure. History uses native List swipe actions with the existing delete confirmation/archive behavior. The Workout tab uses the supported `figure.mixed.cardio` SF Symbol in both tab implementations.

Watch Start uses the app's green primary pill. Changing Strength/Cardio recreates the wheel picker immediately, keeping each mode's saved choice. This Week sizes rings from width rather than changing available height, adds top spacing, and uses the launcher's selected page to own the title. Suggested workout review shows each set's reps and load, prefills from local or phone-synced last-set history, and passes those reviewed values into Start. Captured strength HR is saved to the local session used by Watch history as well as sent to the phone.

## Requirement audit and verification

| Report | Production entry point | Observable result / regression or device check |
| --- | --- | --- |
| Heading and larger weekly rings | `WeeklyIntentRingsCard` | Check “Totals this week,” substantially larger rings, Strength/Cardio values, small phone and large Dynamic Type. Heading supplied in all nine locales. |
| Watch green Start | `WatchPrimaryStartButton` → `WatchPillStyle.primary` | Open Watch home and a strength preview; Start uses the existing green gradient and dark foreground. |
| Watch mode picker delayed | `WatchHomeStartControls` picker identity | Tap Cardio then Strength without touching the wheel; choices and selection change immediately. Existing `WatchHomeWorkoutSelectionTests` guard separate saved choices. Rendered timing needs a Watch. |
| This Week flashes/resizes and lacks title spacing | `WatchRootView`, `WatchWeekView`, `WatchMyWorkoutsView` | Swipe home → This Week repeatedly after cold launch, then after a summary update. Title stays correct, top margin remains, rings retain size; check smaller Watch and large text. |
| Watch strength HR absent in history | `WatchStrengthFlowModel.recordHeartRate` → stored session → `WatchMyWorkoutDestination` | Strength HR regression now reopens the saved session through a fresh context and builds its historical summary; repeated/empty capture cannot erase samples. Device: record a strength workout with HR, finish, view history immediately and after relaunch, and compare with phone. |
| Phone history swipe opens workout | `HistoryView.workoutTimeline` List + trailing swipe action | Swipe strength and cardio rows; Delete appears without opening detail. Confirm → row disappears; Archive → Restore returns it. A normal tap still opens detail. This is native SwiftUI gesture integration and requires device verification. |
| Empty Workout tab icon | `RootTabView.nativeTabs` | Supported activity figure appears when selected/unselected, in light/dark mode. |
| Rep structure next to person and selection mark | `WorkoutPlanEditor.workoutRepStructureControls`, `RepSchemeSheet` | Select 8-8-8 for Me; see “Me: 8-8-8”; reopen and see checkmark. Repeat for partner and a custom ladder. `WorkoutPlanRepStructureTests` guard actual structure and performer/load preservation. |
| Phone suggested load/reps placeholders | editor initial `seedSuggestedOwnerDefaults` → `PartnerPlanResolver.suggestedOwnerSets` | Given last set 205 lb × 8, generated missing targets start with that exact canonical load and reps; edits remain authoritative. New test guards count/identity, no history and explicit loads. Check initial suggestion and Suggest Another. |
| Suggested preview missing sets/reps | `WatchHomeSuggestedStrengthView` → `prefilledSuggestion` → `WatchStrengthPreview` | Watch preview shows per-set targets and Start keeps them. New `WatchStrengthPreviewSetupTests` case guards review/start parity; check with phone reachable/unreachable and a rep override. Phone compact preview already renders its now-filled sets. |
| Plan initially in edit mode | suggested-plan sheet in `HomeView+Dashboard` | Open a suggested plan: compact preview appears; pencil enters editing; switching back preserves edits. Other plan routes retain the existing preview default. |
| TestFlight crash | Read-only crash-intake inspection | Latest inspected run: https://github.com/johnarleyburns/parso-workout-ios-app/actions/runs/44076730657 (2026-11-17 11:44 UTC). Collector listed 43 reports, 14 in scan window, all 14 duplicates. No new report was imported. Existing reports include #578 (build 1037) and #582 (Watch sync). This does not establish whether the user's new crash has reached Apple's feedback API; no new crash fix is claimed. |

## Validation status

- PASS: `git diff --check`; Swift frontend syntax parsing of every changed Swift file.
- PASS: test-pyramid, history-safety, design-token and Watch handler-isolation guardrails.
- PASS: catalog delta inspection confirms the new heading is the only catalog change and has all nine locale values.
- BLOCKED: focused `swift test --package-path CadenceCore --parallel --filter 'WorkoutPlanRepStructureTests|WatchStrengthFlowModelTests.testDirectSummaryHeartRateSnapshotIsKeptAndIdempotent'` fails at compilation because this Linux host has no SwiftData. Regressions were added before implementation, but failing-to-passing behavior evidence is **not yet available**. Full package tests, new Watch preview test and generic iPhone/Watch builds must run on the macOS PR runner before merge.
- EXISTING FAILURES: localization coverage reports missing translations in existing keys plus an existing plural guard failure in `ExerciseSelectionPolicy.swift:47`. Accessibility ratchet reports existing `.minimumScaleFactor(0.5)` in `WatchSetKeypadView.swift:145`. Neither source is modified here.
- No simulator was booted. Compiler-driven localization extraction requires Xcode and remains to be run.

Before merge, require package tests and generic destination builds on macOS; then complete the device checklist above on the released build. No TestFlight build contains these local changes yet; record the exact version/build only after release reconciliation reports it VALID. Historical Watch workouts that never saved local HR still depend on the existing phone/CloudKit copy syncing back; this change does not fabricate or reconstruct missing physiological data.
