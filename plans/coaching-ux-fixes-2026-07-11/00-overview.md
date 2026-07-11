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
- P2: pending (stacks on P1).
</content>
</invoke>
