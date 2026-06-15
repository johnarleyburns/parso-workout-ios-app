# Strength pivot — current state

Progress tracker for the strength-pivot roadmap
(`plans/strength-pivot/2026-06-15/00-overview.md`). One row per phase.

| Phase | Deliverable | Status |
|------|-------------|--------|
| P0 | Strategy + decisions locked | ✅ done (`00-overview.md`, `decisions.md`; PR #30) |
| **P1** | **Remove CrossFit (tag then delete) + Boxing→cardio** | ✅ **done** — branch `p1/remove-crossfit` |
| P2 | CC0 library import (free-exercise-db) | ⬜ not started |
| P3 | Engine core (read-only insights) + Coach-Home | ⬜ not started (needs P2) |
| P4 | Assessments v1 (strength / strength-endurance) | ⬜ not started (needs P3) |
| P5 | Prescriptive engine + live Coach card | ⬜ not started (needs P3) |
| P6 | Cardio/anaerobic assessments + HIIT loop | ⬜ not started (needs P4,P5) |
| P7 | Reposition (onboarding, goals, App Store) | ⬜ not started (needs P5) |

## P1 — what shipped (2026-06-15)
- **Preservation:** annotated tag `crossfit-preserved-v1` on the pre-removal commit
  (`33c1e63`), pushed to origin — recoverable base for a future CrossFit app.
- **CadenceCore:** removed `BenchmarkWorkouts` ("the Girls"), `PlanSource.crossfit`,
  and the CrossFit-only `WorkoutScheme` cases (`forTime`/`amrap`/`emom`/
  `roundsForTime`); `WorkoutScheme` is now `.strength` only. Removed the
  `.crossfit` `WorkoutType` case. Kept `WorkoutPlan`/`PlanItem`/`StrengthPresets`/
  `PlanCatalog` + `.strength` (reused by the strength path).
- **App:** deleted `CrossFitPickerView`; recreated the shared preset preview as
  strength-only `PlanPreviewView` (in `WeightsStartView.swift`); removed the
  CrossFit Start tile, the CrossFit manual-log path (`LogCrossFitPicker`), the
  `forTime` ghost-card rendering in `SessionView`, and the crossfit.com links.
  Preview a11y IDs renamed `crossfit.preview.*` → `plan.preview.*`.
- **Boxing:** unchanged — still a cardio/interval workout (timer, round bell via
  `IntervalCues`, warm-up gate, counts as cardio time). Verify-only.
- **Legacy data:** existing "CrossFit – …" sessions still render read-only (their
  now-unknown `planKey` resolves to nil; `Models.symbol` keeps the functional
  glyph for legacy titles). Regression covered in `WorkoutPlanTests`
  (`testLegacyCrossFitKeyResolvesToNil`) + `WorkoutSummaryDataTests`.
- **Tests:** `swift test` green (160, 0 failures). App + UI test targets compile
  (`xcodebuild build` / `build-for-testing` succeed). `FR8CrossFitUITests` deleted;
  CrossFit cases in FR13 removed; FR7/FR9/FR10 updated to the new preview IDs.

## Note on branching
P1 branched off `main` (which already contained all CrossFit code — the plan's
"un-merged stack #19–#29" concern was moot). The plan docs themselves live on the
`docs/strength-pivot-plan` branch (PR #30, base `main`); this file lands via the P1
PR and will coexist with the plan docs once both merge to `main`.
