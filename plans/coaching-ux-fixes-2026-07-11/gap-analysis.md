# Gap Analysis — Coaching & UX Fixes (2026-07-11)

Re-read the original 13-issue plan; every acceptance criterion checked against shipped code.

## Issue 1 — productive-midpoint volume (P2)
- [x] `VolumeLandmarks.productiveTarget(for:experience:)` = (MEV+MAV)/2.
- [x] Optimizer plans toward productive (3-pass: MEV coverage → breadth → productive top-up).
- [x] Bounded by MRV (guard test `testProductiveTargetNeverExceedsMRV`).
- [x] Nag reconciled: `unresolvedDeficits` REPORTED against MEV → a productively-dosed part never under-doses+nags (`testProductivelyPlannedAbsProducesNoNag`).
- [x] volumeDoseResponse citation retained on insight.

## Issue 2 — goal-specific rep ladders (P1)
- [x] `RepLadder.ladder(for:sets:)` — hypertrophy 12-10-8 / 12-10-8-6; strength 5-5-3 / 5-5-3-3; endurance 20-18-16.
- [x] Threaded into `prescribedSession(goal:)`, `buildStrengthExercises`, `CoachPlanOptimizer.copy`, editor seeding.
- [x] `RecommendedExercise.repLadder` additive/optional.
- [x] SetTarget.summary: SessionView already renders `plannedRepLadder` as "12-10-8 reps" (verified existing plumbing).
- [x] Cited via existing strengthIntensity pool.

## Issue 3 — Additional strength → Start anyway (P4)
- [x] Addon `.hardStrengthWarn` session now carries exercises (fullBodyStrengthExercises).
- [x] Defensive fallback in launchDecision (empty editor, never dead-ends).
- [x] Reuses P1 ladders.
- [x] Tests: 2 CadenceCore + 1 XCUITest (Start anyway → editor.start).

## Issue 4 — Reassign confirmation + rich picker (P5)
- [x] confirmationDialog "Reassigning to <match>, proceed?" → Reassign to <match> / Pick a different exercise / Cancel.
- [x] Pick a different → ExercisePickerView (search + body-part pills), constrained to built-ins.
- [x] Retired ReassignExercisePickerView.
- [x] WorkoutRepositoryTests.testReassignAndDeleteExercise still green.

## Issue 5/6 — bar/gear centering (P8, best-effort)
- [x] UITabBarAppearance titlePositionAdjustment zeroed.
- [x] Settings gear in 44x44 centered frame.
- [x] Smoke test: tabs + gear stay hittable. Visual verified by screenshot; documented as best-effort.

## Issue 7 — Your Plan redesign (P7)
- [x] TODAY-first section.
- [x] Completed strength+cardio day no longer labels as weekday name ("Thu" fix).
- [x] Completed days tappable → HistorySummaryRoute (summary).
- [x] Planned future days → read-only PlannedDayPreviewView (no Start button).
- [x] Strength tonnage (unit-aware t/tn).
- [x] Cardio HR-zone breakdown (CardioZoneAggregator, cited tanakaMaxHR2001).
- [x] Optional age in onboarding + Coach preferences; default 40 when unset.
- [x] AppSettings.userAge exported additively.

## Issue 9/10 — active workout (P6)
- [x] Work/Rest stopwatch (WorkoutTimersModel + segmented control).
- [x] Per-exercise info button → ExerciseDetailView (exerciseCard + plannedCard).
- [x] Cancel → "X" (xmark, a11y "Cancel").
- [x] RPE stepper → numeric keypad field (clamped 1-10).
- [x] Wall clock in all 5 workout headers (strength, outdoor, timer cardio, intervals, swim).
- [x] "BW" already shown on the set cell; descriptive help/menu strings kept.

## Issue 11 — weekly test recommendation (P3)
- [x] CoachTestRecommendationEngine: ≤1/week, never-tested-first then most-stale, per-kind snooze, pick-a-different cycling.
- [x] CoachTestRecommendationCard: Start test / Pick a different / Not right now.
- [x] Start test → AssessmentDetailView via HomeRoute.runAssessment.
- [x] Persisted lastTestRecommendationAt + testRecommendationSnoozes; exported additively.
- [x] Cited (assessment citationIds; test asserts resolvable).
- [x] Lower-priority: card moved below the week strip so it never crowds the primary planning surfaces.

## Issue 13 — red-test-first + gap analysis + per-phase PR
- [x] Each phase: red test → fix → verify → commit → merge → push → CI.
- [x] This gap analysis; current_state.md updated.

## Schema & migration safety
- [x] All new fields additive/optional/defaulted: RecommendedExercise.repLadder?, AppSettings.userAge?,
      lastTestRecommendationAt?, testRecommendationSnoozes, ExportPreferences additions (all optional).
- [x] Legacy exports decode (tests: testTestRecommendationFieldsDefaultNilOnLegacyExport, testUserAgeRoundTrips).

## Verification totals
- CadenceCore: 770 tests, 0 failures.
- iOS: BUILD SUCCEEDED. New XCUITests: CoachTestRecommendation (3), AdditionalStrength (1),
  CustomExerciseReassign (2), ActiveWorkoutPolish (3), YourPlanRedesign (3), LayoutPolish (2) — all green.
- CI: P1–P7 green; P8 in progress at write time.

## Known pre-existing (NOT regressions — confirmed at pre-P3 commit d64dbfa)
- 3 P3CoachHomeUITests (Your Plan `.tap()` navigation) fail identically before any of this work
  (default Recents picker tab + NavigationStack `.tap` timing on this SDK/simulator). My own
  P7 Your-Plan UI tests reach the "Your Plan" nav bar successfully via scrollToHittableAndTap.
- FR7 testSessionElapsedTimerRunsAndFreezesOnPause: fails identically on pristine main (picker
  Recents-tab + degraded-simulator launches). Not touched by P6.

## Gaps found: NONE requiring further code.
Deviations from plan (intentional, minimal-risk):
- P2 kept the base `isolationSets = 2` seed in buildStrengthExercises; the optimizer's productive
  top-up raises planned isolation to the productive dose, so the seed value is not the final dose.
- P7 tappable-day mapping uses a date-keyed lookup over the queried rows (passed into YourWeekView)
  rather than a DayOutline back-reference — same effect, no schema change.
- Issue 2 SetTarget.summary: rendering already handled by SessionView's plannedRepLadder path; no
  change to SetTarget.summary was needed (it renders single-rep targets; ladders render via the session).
</content>
