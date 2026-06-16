# Strength pivot — current state

Progress tracker for the strength-pivot roadmap
(`plans/strength-pivot/2026-06-15/00-overview.md`). One row per phase.

| Phase | Deliverable | Status |
|------|-------------|--------|
| P0 | Strategy + decisions locked | ✅ done (`00-overview.md`, `decisions.md`; PR #30) |
| **P1** | **Remove CrossFit (tag then delete) + Boxing→cardio** | ✅ **done** — branch `p1/remove-crossfit` |
| **P2** | **CC0 library import (free-exercise-db)** | ✅ **done** — branch `p2/cc0-library` (stacked on P1) |
| **P3** | **Engine core (read-only insights) + Coach-Home + tab bar** | ✅ **done + merged** — PRs #33 + #34 (stacked) on `main` |
| **P4** | **Assessments v1 (strength / strength-endurance)** | ✅ **done + merged** — PR #35 on `main` |
| **P5.1** | **Prescriptive engine core (CadenceCore) + CITATIONS.md** | ✅ **done** — branch `p5/prescriptive-engine` (off merged P4) |
| P5.2 | Live Coach card surfacing the prescription | ⬜ not started (needs P5.1) |
| P5.3 | "Do this workout" → logger pre-fill | ⬜ not started (needs P5.2) |
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

## P3 — what shipped (2026-06-15)
Two stacked PRs (`p3/engine-core` → `p3/coach-home`). The **read-only** slice of the
Scientific Expert Engine (§03) + the Coach-driven Home (§05) + an Apple-HIG tab bar.

- **Engine core (CadenceCore, pure):**
  - `TrainingGoal` (D4: strength/hypertrophy/endurance) + `ExperienceLevel`
    (beginner/intermediate/advanced; scales volume landmarks).
  - `Citation` + `CitationRegistry` — `schoenfeld2021`, `volumeDoseResponse`,
    `frequencyMeta`. **Every insight is cited (D3).** Full `CITATIONS.md` pass still
    precedes P5 (D9).
  - `VolumeLandmarks` — MEV/MAV/MRV weekly-set bands per `BodyPart`, experience-scaled,
    with `VolumeZone` classification.
  - `TrainingFacts.make(sessions:…)` — pure snapshot: weekly sets/part (primary 1.0,
    secondary 0.5), frequency/part, e1RM trend (last 7d vs prior 7d, ±2% noise band),
    intensity distribution (heavy/moderate/light vs each lift's best e1RM), avg RPE +
    derived RIR, days since last. Reuses `BodyPart`, `WorkoutMath`, mirrors `WeeklyStats`.
  - `Insight` / `InsightRule` / `KnowledgeBase.p3Rules` (volume · e1RM trend ·
    frequency · intensity×goal) / `InsightEngine.run` — forward-chains, dedupes by id,
    ranks by severity then priority; **cold-start fallback so the card is never empty.**
    Read-only: no prescriptions/actions yet (P5).
- **App (Coach-Home + tab bar):**
  - `RootTabView` — bottom tab bar **Workout / Plan / Library**. Workout = the existing
    `HomeView`; **Plan + Library are intentional placeholders** (`ComingSoonPlaceholder`)
    wired but empty in P3 (goals/calendar/favorites and library/routines/studies land
    later). `CadenceApp` now hosts `RootTabView`.
  - `CoachCardView` is Home's **hero**: top insight + an expandable "Why / the science"
    (explicit toggle button, not a `DisclosureGroup`, for testable a11y) with a tappable
    `Citation` link; "See all insights" → `CoachInsightsView`. Non-medical footnote (D6).
    `Start Workout` demoted to action #2, `Log Workout` #3; the batch-8 stat tiles moved
    below under a **"This week"** header (ids/tap behavior unchanged).
  - Settings: a **Coach** section appended at the bottom (per the append convention) —
    training-goal + experience pickers, persisted in `AppSettings`
    (`trainingGoal` default hypertrophy, `experienceLevel` default intermediate). Full
    onboarding goal intake is still P7.
- **Schema:** additive only — no SwiftData change (`rpe` already existed; settings are
  UserDefaults-backed; no engine state persisted, insights recompute from facts).
- **a11y gotcha fixed:** the card's `background`+`overlay`+`accessibilityIdentifier`
  collapsed it into one element; `.accessibilityElement(children: .contain)` keeps
  `coach.card.why` / `.citation` addressable.
- **Tests:** `swift test` green (**183**, +18: `VolumeLandmarks`, `TrainingFacts`,
  `InsightEngine` incl. D3-citation + cold-start invariants). UI `P3CoachHomeUITests`
  (tab bar + placeholders, cited Coach card, Coach settings) pass, plus FR15 batch-8
  tile tests re-verified against the reshuffle. App `build` succeeds (iPhone 16, iOS 18.1).

## P4 — what shipped (2026-06-16)
Assessments v1 (§04): the standardized, repeatable **strength + strength-endurance**
battery the engine tracks longitudinally. Aerobic (VO₂max) + anaerobic (Wingate)
kinds remain deferred to P6.

- **Data model (CadenceCore, CloudKit-safe):** `Assessment` `@Model` — every property
  optional/defaulted, stable `id`/`updatedAt`/`originDevice`, no unique constraints.
  Stores the result `value` in the kind's unit plus raw `inputWeight`/`inputReps` so an
  estimate can be recomputed if equations improve. Added `Assessment.self` to the store
  schema (additive).
  - `AssessmentKind` (7): `e1RM`, `repMax` (strength); `pushupMax`, `pullupMax`,
    `bodyweightSquatMax`, `plankHold`, `hollowHold` (strength-endurance). Each carries
    `category` / `unit` (weightKg·reps·seconds) / `concernsLift` / `higherIsBetter` /
    `displayName` / `symbol` / guided non-medical `protocolText`.
  - `seriesKey` groups results into longitudinal series — by kind alone for bodyweight
    tests, by kind + lift for `e1RM`/`repMax`.
- **Pure math (`AssessmentMath`, `swift test`-verified):**
  - `summaries(from:)` collapses raw rows into one `AssessmentSummary` per series
    (baseline/latest/best/count, sorted most-recent first).
  - **MDC guardrail** (`minimalDetectableChange`) so noise isn't read as progress:
    ~3% for kg (floor 1), 10% for reps (floor 1), 10% for seconds (floor 3) → drives
    `AssessmentTrend` (improved/declined/unchanged/single).
  - Re-test cadence: `isRetestDue` at `defaultRetestDays = 42` (D5 ~6–8 wk).
  - `e1RM(weight:reps:formula:)` reuses `WorkoutMath.estimated1RM`.
- **Engine integration (read-only, still cited — D3/D6):**
  - `TrainingFacts.make` now ingests `assessments:` (defaulted), precomputing
    `assessments` + `assessmentsDueForRetest` summaries with an injectable `now` so rules
    stay pure/deterministic. Cold-start is bypassed once any assessment exists.
  - New `InsightKind.assessment`; `KnowledgeBase.p4Rules` = `assessmentProgress`
    (info on gain / attention on decline, unit-aware "+12 reps") + `assessmentRetest`
    (nudge stale series). `activeRules = p3Rules + p4Rules`.
  - New citation `oneRMEstimation` (LeSuer et al., 1997, JSCR 11(4)) for strength-series
    insights; strength-endurance cites `schoenfeld2021`.
- **App (Plan tab is now real):**
  - `PlanView` = the assessment battery hub — intro + a section per `AssessmentCategory`,
    each row showing the latest value + a trend pill, → `AssessmentDetailView`.
  - `AssessmentDetailView` — the protocol, a "Record result" action, and per-series
    Swift-Charts trend + longitudinal log (kg series chart in the user's unit).
  - `RecordAssessmentView` — unit-adaptive sheet: e1RM (lift + load×reps, live e1RM),
    rep-max (lift + load + reps), bodyweight rep count, or a min/sec hold picker. Saves an
    `Assessment` to the context.
  - `HomeView` now `@Query`s assessments and feeds them to `TrainingFacts.make`, so the
    Coach card surfaces assessment progress/retest insights. `CoachCardView` got the
    `.assessment` symbol case. Library stays a placeholder.
- **Tests:** `swift test` green (**201**, +18: `AssessmentMathTests`,
  `AssessmentInsightTests`). UI `P4AssessmentsUITests` (battery list + record→log) and the
  updated `P3CoachHomeUITests` (Plan tab now the assessments hub) pass. App `build`
  succeeds (iPhone 16, iOS 18.1).

## P5.1 — what shipped (2026-06-16)
The prescriptive half of the Scientific Expert Engine (§03), pure `CadenceCore` only —
the engine that turns `TrainingFacts` into concrete, cited *actions*. Surfaced in the
Coach card in P5.2; "Do this" logger pre-fill in P5.3.

- **D9 citations pass (gate before the prescriptive phase):** new `docs/CITATIONS.md`
  curates the reference list and documents how each is used + its caveats; the in-app
  source of truth stays `CitationRegistry`. Added `rpeAutoregulation` (Helms, Cronin,
  Storey & Zourdos, 2016, *Strength Cond J* 38(4)) for the progression/deload rules.
- **`TrainingGoal` → prescription params:** `repRange` (strength 3–5, hypertrophy 6–12,
  endurance 15–20) + `targetRIR` (2/1/2), from the load/rep continuum (`schoenfeld2021`).
- **`TrainingFacts` (additive):** new `LiftSnapshot` per lift (heaviest loaded working
  set + reps + best e1RM + trend + primary part) and `liftSnapshots: [String: LiftSnapshot]`,
  computed in `make` — the basis for next-session targets. Defaulted in the init, so the
  P3/P4 callers (`HomeView`, tests) are untouched.
- **Prescriptive engine (pure, deterministic — mirrors `InsightEngine`):**
  - `Recommendation` (+ `RecommendationKind`, `RecommendationConfidence`, `SetTarget`) —
    the P5 evolution of `Insight`: a cited (D3) "why" plus a concrete `action` and a
    structured `SetTarget` (sets × rep range × optional load kg × RIR) the logger can
    adopt. `SetTarget.summary(unit:)` renders in the user's unit; the engine stays
    canonical-kg.
  - `KnowledgeBase.p5Rules` = **progression** (double progression — add reps to the top
    of the range, then add load + reset; cites `rpeAutoregulation`) · **deload** (a
    declining e1RM trend → one lighter week ~10% off, fewer sets, +RIR) · **addVolume**
    (a part below MEV → add N sets; cites `volumeDoseResponse`). Plus a `starter(goal:
    experience:)` cold-start.
  - `RecommendationEngine.run` forward-chains, dedupes by id, ranks priority → confidence
    → id; falls back to `[starter]` so the card is never empty. `top(_:)` for the hero.
- **No UI / no schema change.** App untouched; CadenceCore API changes are all additive.
- **Tests:** `swift test` green (**213**, +12: `RecommendationEngineTests` — double
  progression both branches, deload vs progression routing + ranking, add-volume MEV
  boundary, cold-start starter, every-rec-cited, idempotence, load rounding, `make`
  wiring). App `build` succeeds (iPhone 17 Pro sim, iOS 26.5 — iPhone 16/18.1 not in
  this env).

## Note on branching
P1 branched off `main` (which already contained all CrossFit code — the plan's
"un-merged stack #19–#29" concern was moot). The plan docs themselves live on the
`docs/strength-pivot-plan` branch (PR #30, base `main`); this file lands via the P1
PR and will coexist with the plan docs once both merge to `main`.
