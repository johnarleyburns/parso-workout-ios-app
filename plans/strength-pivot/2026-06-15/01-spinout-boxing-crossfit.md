# 01 — Remove CrossFit; keep Boxing as cardio

## Decision (locked 2026-06-15, D1)
- **CrossFit: REMOVE.** Breadth dilutes the "science-based lifting coach" identity and
  CrossFit has its own community/competitors (SugarWOD/Wodify). **`git tag` the code
  before deleting** so it's fully recoverable for a future separate `Cadence CrossFit`
  app, then delete it from this codebase. (Tag, not quarantine — keep the strength app
  clean.)
- **Boxing: KEEP, reclassified as cardio-only.** Boxing stays in the app as a normal
  cardio/interval workout (it already routes through `IntervalCues`/`CardioType`); it
  is *not* spun out and gets *no* special first-class treatment beyond cardio.
- **HIIT: stays** and migrates into the science engine (`04`).

## What's in scope to quarantine (from the current code)
- **CrossFit**: `CadenceCore` `WorkoutPlan`, `BenchmarkWorkouts` ("The Girls"),
  `PlanCatalog`; app `Features/Home/CrossFitPickerView.swift`, the `.crossfit`
  `WorkoutType` case, planned-session/Rx rendering in `SessionView`, the manual-log
  CrossFit path (`LogStrengthViews.LogCrossFitPicker`), `FR8CrossFitUITests`.
- **Boxing**: the `.boxing` `WorkoutType`/`CardioType`, boxing `IntervalPlan`
  protocols + bell cadence in `IntervalCues`, boxing tiles.
- Note **HIIT stays** — it migrates into the science engine (`04`), it is *not*
  quarantined.

## In scope to REMOVE (CrossFit)
- Core: `WorkoutPlan`, `BenchmarkWorkouts` ("The Girls"), `PlanCatalog`, the planned-
  session machinery used only by CrossFit; the `.crossfit` `WorkoutType` case.
- App: `Features/Home/CrossFitPickerView.swift`, the CrossFit Start tile, planned-card/
  Rx rendering in `SessionView`, the manual-log CrossFit path (`LogCrossFitPicker` +
  its tile in `LogWorkoutPicker`), `FR8CrossFitUITests`, CrossFit seeds.
- **Keep** the generic strength-plan/planned-exercise plumbing IF the engine will reuse
  it for prescribed sessions (audit: `plannedExerciseNames` stays; benchmark-specific
  `WorkoutPlan`/`PlanCatalog` go). Don't break `reuseSession`/manual strength logging.

## Boxing → cardio (keep)
- Leave `.boxing` as a `CardioType`/interval workout; ensure it's presented only under
  cardio surfaces (Start picker cardio group, cardio-min quick-start). No CrossFit
  coupling. Bell audio stays (HIIT/strength use it too).

## Approach — tag, then delete (P1)
1. **Preserve first**: `git tag crossfit-preserved-v1` (annotated) on the commit that
   still contains all CrossFit code, and push the tag. This is the recoverable
   reference for a future `Cadence CrossFit` app. Note the tag in `README`/this doc.
2. **Delete** the CrossFit files/types above; remove `.crossfit` from `WorkoutType`
   and all switches; delete `FR8CrossFitUITests` and CrossFit seeds.
3. **History compatibility**: any *existing* logged session whose title contains
   "CrossFit" must still render in history read-only (it's just a `WorkoutSession` —
   removing the *creation* path doesn't delete user data). Verify the history/summary
   path has no hard `WorkoutPlan` dependency before deleting `PlanCatalog`.
4. **Boxing audit**: confirm `.boxing` still starts (as cardio/interval) after CrossFit
   removal; keep `FR` boxing coverage if any.

## Sequencing note (important)
CrossFit code is spread across several **un-merged** stacked PRs (#19–#29). Decide with
the user whether to **merge the stack to `main` first**, then do the removal on a clean
`main` (recommended — simpler diff, the tag captures pre-removal state), or branch the
removal off the current tip. (See the pending merge question.)

## Testing / verify (P1)
- `git tag` exists + pushed before any deletion.
- App builds; Start/Log surfaces show **no CrossFit**; **Boxing still starts** as cardio;
  HIIT intact. `swift test` green (CrossFit tests removed, not skipped). A seeded legacy
  "CrossFit – Fran" session still opens its summary in history (no crash).
