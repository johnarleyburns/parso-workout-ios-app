# Strength pivot — current state

Progress tracker for the strength-pivot roadmap
(`plans/strength-pivot/2026-06-15/00-overview.md`). One row per phase.

| Phase | Deliverable | Status |
|------|-------------|--------|
| P0 | Strategy + decisions locked | ✅ done (`00-overview.md`, `decisions.md`; PR #30) |
| **P1** | **Remove CrossFit (tag then delete) + Boxing→cardio** | ✅ **done** — branch `p1/remove-crossfit` |
| **P2** | **CC0 library import (free-exercise-db)** | ✅ **done** — branch `p2/cc0-library` (stacked on P1) |
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

## P2 — what shipped (2026-06-15)
- **Vendored source:** `free-exercise-db` (Unlicense / public-domain) `dist/exercises.json`
  at pinned commit `b0eed06`, bundled as a CadenceCore resource
  (`Resources/free-exercise-db.json`) with its LICENSE + `CREDITS.md` (D2).
- **On-device transform:** `ImportedExerciseLibrary` — a pure, `swift test`-verified
  function maps their coarse taxonomy onto ours: 17 muscle strings → `MuscleCatalog`
  ids ("middle back"→rhomboids, "neck"→traps), equipment ("e-z curl bar"→barbell;
  foam-roll/exercise-ball/medicine-ball/other → nil), and a movement-split
  `ExerciseCategory` derived from region + force. Carries instructions + image id +
  level. 873 entries → all transform (every entry has ≥1 muscle).
- **Merged catalog:** `ExerciseLibrary.starter` = curated (170) + imported tail
  (~830 after name-dedup) ≈ **1000 movements**; curated facets win on name collision
  (43 overlaps). `curated`/`imported`/`starter` split exposed for tests.
- **Schema (additive):** `instructions: [String]`, `imageName: String?`,
  `level: String?` on `ExerciseTemplate` + `Exercise` (delimited-String / optional,
  CloudKit-safe). Seeding backfills these onto already-faceted built-ins; `seedVersion`
  unchanged (backfill is keyed on field presence, not version).
- **Images:** 873 public-domain demo images downscaled to 400px JPEG q60
  (~19 MB total) bundled at `Resources/exercise-images/<id>.jpg`; resolved offline via
  `ExerciseLibrary.imageURL(forImageName:)`. (One image/exercise; a 2nd pose or
  on-demand asset pack is a possible P2.1 per D8.)
- **EXRX retired:** removed `exrxReferenceURL`; the picker's info button now pushes an
  in-app `ExerciseDetailView` (image + muscles + numbered instructions, fully offline).
  A11y id `picker.exrx.*` → `picker.info.*`; `FR15Batch8UITests` updated.
- **Tests:** `swift test` green (165, +5 in `ImportedExerciseLibraryTests`; dropped the
  EXRX URL test). App `build` + `build-for-testing` succeed on iPhone 16 (iOS 18.1).

## Note on branching
P1 branched off `main` (which already contained all CrossFit code — the plan's
"un-merged stack #19–#29" concern was moot). The plan docs themselves live on the
`docs/strength-pivot-plan` branch (PR #30, base `main`); this file lands via the P1
PR and will coexist with the plan docs once both merge to `main`.
