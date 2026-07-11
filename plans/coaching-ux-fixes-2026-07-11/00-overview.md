# Cladiron — Coaching & UX Fixes (2026-07-11)

Live plan tracker. Source: user's 13-issue report + confirmed product decisions.
Method: red test first → fix → gap analysis → commit/merge/push/CI per phase.

## Confirmed decisions
- Issue 1 → target the productive midpoint (MEV→MAV), not the MEV floor.
- Issue 2 → goal-specific descending rep ladders (hypertrophy 12-10-8 / 12-10-8-6;
  strength 5-5-3 / 5-5-3-3; endurance high-rep 20-18-15), cited to load/rep continuum.
- Issue 7 → lightweight read-only planned-day preview (no Start button off-day).
- Issues 5/6 → best-effort bar-centering; document if a device artifact.

## Phases (one branch + PR each)
| Phase | Issues | Area | Depends |
|-------|--------|------|---------|
| P1 | 2 | Goal-specific rep ladders (CadenceCore) | — |
| P2 | 1 | Productive-midpoint volume targeting + reconcile nag | P1 |
| P3 | 11 | Weekly test-recommendation injection w/ dismiss | — |
| P4 | 3 | "Additional strength → Start anyway" real session | — |
| P5 | 4 | Custom-exercise Reassign confirmation + rich picker | — |
| P6 | 9,10 | Active-workout: work/rest timer, info, BW/X/RPE, wall clock | — |
| P7 | 7 | "Your Plan" redesign: TODAY-first, tappable days, tonnage, HR zones, age | P1/P2 |
| P8 | 5,6,12 | Bar centering + Progress Frequency box height | — |

## Status
- P1: DONE — `RepLadder` generator + threaded into both prescription paths
  (`Recommendation.prescribedSession(goal:)`, `CoachSession.buildStrengthExercises`,
  `CoachPlanOptimizer.copy`, `EditablePlan.from(coach:)`/`from(recommendation:goal:)`).
  Added `RecommendedExercise.repLadder` (additive/optional). SessionView already
  renders `plannedRepLadder` as "12-10-8 reps". Tests: RepLadderTests (12) +
  5 new prescription cases. Full suite 741 green; iOS build SUCCEEDED.
- P2: DONE (stacks on P1) — `VolumeLandmarks.productiveTarget(for:experience:)`
  = MEV/MAV midpoint. Optimizer now plans toward productive (3-pass reshaping:
  MEV coverage -> breadth -> productive top-up, all MRV-bounded) while
  `unresolvedDeficits` are REPORTED against MEV so a productively-dosed part
  never both under-doses and nags. Tests: +3 optimizer (productive target, MRV
  guard, nag reconciliation). Full suite 744 green; iOS build SUCCEEDED.
- P3: DONE (independent, off main) — pure `CoachTestRecommendationEngine` (<=1/week
  gate, never-tested-first then most-stale, per-kind snooze, "pick a different"
  cycling). `CoachTestRecommendationCard` on Home (Start test / Pick a different /
  Not right now) routing into `AssessmentDetailView` via `HomeRoute.runAssessment`.
  Persisted `lastTestRecommendationAt` + `testRecommendationSnoozes` in AppSettings,
  exported via ExportPreferences (additive). Tests: 8 engine + 2 export round-trip
  + 3 XCUITests. Core 754 green; iOS build SUCCEEDED; coach UI suites green.
  NOTE: added the two new settings keys to the UI-test clear list (stale
  lastTestRecommendationAt was gating the card in tests).
- P4: DONE (independent, off main) — root cause: addon `.hardStrengthWarn` session
  had no `exercises` so `EditablePlan.from(coach:)` returned nil -> dead-end. Fix:
  `CoachSession.fullBodyStrengthExercises(facts:)` public wrapper populates the
  addon session (reusing P1 ladders); `launchDecision` falls back to an empty
  editor rather than silently returning. Tests: 2 CadenceCore + 1 XCUITest
  (Start anyway -> editor). Core 756 green; iOS build SUCCEEDED.
- P5: pending.</content>
</invoke>
- P5: DONE (independent, off main) — Reassign now uses a `.confirmationDialog`
  ("Reassigning to <match>, proceed?") -> Reassign to <match> (direct) / Pick a
  different exercise (opens the rich `ExercisePickerView` with search + body-part
  pills, constrained to built-ins) / Cancel. Retired the plain
  `ReassignExercisePickerView`. Added `settings.customExercises` a11y id +
  `customExerciseNeedsReassign` seed. Tests: 2 XCUITests; WorkoutRepositoryTests
  (24) still green. iOS build SUCCEEDED.
- P6: pending.
- P6: DONE (issues 9 & 10) — pure `WorkoutTimersModel` (work/rest stopwatch, banks
  spans on switch; 6 unit tests). `WorkoutElapsedHeader` gains a wall clock
  (top-left) + Work/Rest segmented stopwatch (right). New reusable `WallClockLabel`
  added to strength + outdoor + timer-cardio + interval + swim headers. Per-exercise
  info button (i) -> ExerciseDetailView on both exerciseCard & plannedCard. Inline
  editor Cancel -> "X" (xmark, a11y "Cancel"); RPE stepper -> numeric keypad field.
  Tests: 6 CadenceCore + 3 XCUITests. Core 762 green; iOS build SUCCEEDED.
  NOTE: FR7 testSessionElapsedTimerRunsAndFreezesOnPause fails identically on
  pristine main (pre-existing picker-Recents-tab + degraded-sim flake), not a P6 regression.
- P7: pending.
- P7: DONE (stacks on P1/P2) — Your Plan redesign. WeeklyPlan completed strength+cardio
  day no longer collapses to a weekday name ("Thu") — describes the sessions. New pure
  `CardioZoneAggregator.weeklyZoneMinutes` (HR-sample distribution or modality estimate)
  + `WorkoutMath.tonnageLabel` (unit-aware t/tn) + public `CardioMath.defaultMaxHR`.
  YourWeekView: TODAY-first section, tappable completed days -> HistorySummaryRoute,
  planned future days -> read-only `PlannedDayPreviewView` (no Start), strength tonnage,
  cardio HR-zone breakdown cited to tanakaMaxHR2001. Optional age in onboarding +
  Coach preferences; AppSettings.userAge exported (additive). Tests: 7 CadenceCore
  (zones/tonnage/HRmax/label) + 1 age export + 3 XCUITests. Core 770 green; iOS build SUCCEEDED.
  NOTE: 3 P3CoachHomeUITests (Your Plan .tap navigation) fail identically at pre-P3
  commit d64dbfa — pre-existing, not a P7 regression; my P7 UI tests reach Your Plan fine.
- P8: pending.
- P8: DONE (issues 5, 6, 12) — issue 12: added `equalHeight` to the Progress card
  builder; Effort + Frequency now `.frame(maxHeight: .infinity)` so the side-by-side
  row matches the taller card. Issues 5/6 (best-effort): `UITabBarAppearance` with
  zeroed `titlePositionAdjustment` in RootTabView.init for consistent icon/title
  vertical centering; Settings gear wrapped in a 44x44 centered frame. Tests: 2
  XCUITests (equal card height; tabs + gear stay hittable). Visual centering verified
  by simulator screenshot; if any residual offset is a device/OS rendering artifact it is
  documented here rather than forced. Core 770 green; iOS build SUCCEEDED.
