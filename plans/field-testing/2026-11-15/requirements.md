# Field-testing release changes — 2026-11-15

All items are pending investigation/implementation unless a PR and verification are recorded here.
One PR per change; enable auto-merge and let required CI checks gate merging.
Never push directly to main. Never boot or run simulators locally or in CI.
Use headless unit tests and generic device builds. Each PR must explicitly state
NO SIMULATORS and include a real-device acceptance checklist; device checks are
not claimed as executed. Existing issue admission is paused via repository variable
CLAUDE_PIPELINE_AUTO_ENABLED=false (verified 2026-11-15).

## Acceptance checklist

- [ ] a — Watch non-weighted entry retains weight-left/reps-right columns. Render
  “Non-Weighted” in two compact lines within the existing weight-number area,
  not two full-width rows. Battle ropes is the reproduction example.
- [ ] b — Remove watch set-count dots. Use the exercise-list circular progress
  indicator on the left and exercise name on the right in two compact lines.
- [ ] c — Shared core, watch and phone use entered total weight without dumbbell
  or isometric doubling (including biceps curls). Explain total weight in info copy.
- [ ] d — An explicit reps override persists through subsequent sets and exercises
  throughout that workout on phone/watch. Weight stays sticky per exercise only.
- [ ] e — Watch home has four rows: strength picker (Quick Start = empty custom,
  Suggested = phone suggestion from today or fresh generation, Previous = existing
  repeat flow), icon+Strength button, cardio picker (three most recent plus
  More.. opening the full list), icon+Cardio button. Remove welcome barbell/copy.
- [ ] f — Phone Today uses the same four controls with the activity ring above.
- [ ] g — Shared ring AND text colors on watch/phone and Strength/Cardio tabs:
  zero = red; strength 1–127 sets = yellow, 128–191 = light green, 192+ = dark
  green; cardio >0 and <150 minutes = yellow, 150–299 = light green, 300+ = dark
  green. Original wording overlaps at zero and 128; these boundaries resolve it.
- [ ] h — Progress selected subtab scrolls into view on entry and selection.
  Strength over time is the default subtab.
- [ ] i1 — Remove Suggest Workout from phone Strength and Cardio tabs.
- [ ] i2 — Remove the “<n> sets” count beside Muscle coverage on Strength.
- [ ] j — Strength List muscle-group weekly volume displays “m/12”, replacing
  verbose maximum/productive-range descriptions.
- [ ] k — Tab-view titles become “Strength this week” and “Cardio this week”.
- [ ] l — Find search field is visible on first entry without scrolling away/back.
- [ ] m — Investigate intermittently missing suggested-strength exercise info
  buttons on phone/watch; make exercise details consistently reachable.
- [ ] n — Remove workout/exercise scheduling capabilities, implementation and
  tests from phone/watch. Preserve drafts that can be started at any time and
  ensure existing persisted user data remains readable.
- [ ] o — Remove voice/talk logging and all supporting implementation/tests on
  phone/watch: Quick talk voice logging, Require review before voice logging,
  Smarter understanding, Raise to talk and associated settings.
- [ ] p — Remove Daily step target from settings; inspect supporting unused logic.
- [ ] q — Remove unreachable Start Workout, Pick Workout and old cardio-picker
  Cardio This Week views. Preserve the Cardio tab's weekly view and reachable
  full-cardio selection used by More... Prove caller replacements before deletion.

## PR audit ledger

Record item → production entry point → regression coverage → PR URL → CI result
→ real-device checklist status. A passing build is not device verification.

| Item | PR | Production entry | Verification |
| --- | --- | --- | --- |
| p | https://github.com/johnarleyburns/parso-workout-ios-app/pull/753 | CoachSchedulePreferencesView | diff/guard pass; CI pending; device pending |
| h | https://github.com/johnarleyburns/parso-workout-ios-app/pull/754 | ProgressQuestionSummaryView | Swift parse/diff/guard pass; existing selection tests in CI; device pending |
| l | https://github.com/johnarleyburns/parso-workout-ios-app/pull/755 | ExercisePickerView | Swift parse/diff/guard pass; CI/device pending |
| a | https://github.com/johnarleyburns/parso-workout-ios-app/pull/756 | WatchSetKeypadView.fields | Swift parse/diff/guard pass; CI/device pending |
| i2 | https://github.com/johnarleyburns/parso-workout-ios-app/pull/757 | WeightsStartView | Swift parse/diff/guard pass; CI/device pending |
| j | https://github.com/johnarleyburns/parso-workout-ios-app/pull/759 | HomeMuscleMapView.muscleList | Swift parse/diff/guard pass; CI/device pending |
| b | https://github.com/johnarleyburns/parso-workout-ios-app/pull/760 | WatchSetCardBuilder, WatchSetKeypadView, WatchStrengthHomeView, shared WatchExerciseProgressRing | ring regressions updated; local package attempt fails: missing SwiftData on Linux; CI/device pending |
| k | https://github.com/johnarleyburns/parso-workout-ios-app/pull/761 | HomeView.Surface.title | Swift parse/diff/guard pass; CI/device pending |
| i1 | https://github.com/johnarleyburns/parso-workout-ios-app/pull/762 | HomeWeekDashboardSection | Swift parse/diff/guard pass; CI/device pending |

PR #757 also updates HomeWeekDashboardSection (the shipped Strength tab), not
only the similarly titled legacy WeightsStartView. Audit document PR: #758.

## Remaining investigation findings

- c: doubling exists in Exercise.prospectiveEffectiveLoadKg and
  SetEntry.effectiveLoadKg (Models.swift); SessionInfoSheets explains per-bell
  entry/doubling. LoadAccountingTests and export/history expectations need review.
- d: inspect shared SessionViewModel and WatchStrengthFlowModel prefill/override
  paths; preserve partner attribution and explicit override vs prescription.
- e/f: WatchReadyCard still renders the welcome block. Phone Today renders
  coach hero/recommendation cards in HomeView+DashboardContent. Wire new pickers
  to actual start flows; do not merely relabel legacy navigation.
- g: phone WeeklyIntentPresenter uses ratio-based three-color tint; watch
  WatchWeekRing uses red/yellow/lightBlue/green. Both need one absolute-threshold
  policy, plus all weekly-tab text/progress bindings and boundary regressions.
- m: phone SuggestExerciseView hides info when exerciseForName returns nil;
  watch WatchSuggestedExerciseView resolves catalog entry and disables Details
  when resolution fails. Investigate catalog readiness/name identity and all
  suggested-workout row entry points before selecting a fix.
- n: scheduling is still reachable in HomeView+Dashboard sheets, timer cardio,
  legacy picker callbacks and CoachSchedulePreferencesView. Remove capabilities
  without destroying existing saved/exported data or draft-start support.
- o: WatchSetKeypadView still depends on WatchQuickTalkController, hold-to-talk
  hints and More dictation. Audit phone services/settings/sync contracts too.
- q: SelectWorkoutView, WeightsStartView and CardioPickerView remain referenced
  from HomeView+Dashboard sheets. Replace reachable routes before deleting views.

All listed PRs have auto-merge requested. Unchecked items are not completed.
Worktree: /tmp/cladiron-field-testing. All branches begin codex/field-.
Local full package tests cannot run because this is Linux and app targets require
Apple SwiftData/SwiftUI; full package/build checks are delegated to required CI.
