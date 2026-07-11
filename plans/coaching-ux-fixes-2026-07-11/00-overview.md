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
