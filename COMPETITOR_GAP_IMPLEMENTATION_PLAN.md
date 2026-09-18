# Competitor-Gap Implementation Plan

Status: implemented and audited — 2026-09-18

## Goal

Close the small set of gaps identified from the Hevy, Strong, and Apple
Fitness/Workout comparison without restoring the retired weekly planner,
adding social/video features, or increasing the primary Today flow's density.

## Scope

### 1. Saved workout reuse

- Make reusable templates reachable from `More` as `Saved Workouts`.
- Let the user create, review, delete, and start a saved workout from that
  surface.
- Starting a template must create a normal Cladiron workout and preserve the
  template name and planned exercises.
- Keep this as a secondary route; do not add a new primary tab or revive the
  weekly coach planner.

### 2. Set-type parity where the model already supports it

- Keep the existing `warmup`, `working`, `backoff`, `amrap`, and `drop` model
  values compatible with persisted data.
- Add explicit `failure` and `superset` semantics to the unified model in a
  backward-compatible way.
- Expose failure/drop/superset controls in manual strength editing and render
  the set kind/group clearly during live workout review.
- Ensure validation, Codable/DB++ bridging, and display remain deterministic.

### 3. Focused progression visibility

- Add an exercise-level progression destination from Exercise Info, using the
  existing history/PR/volume calculations rather than another large Home
  query.
- Show the latest logged date, best estimated 1RM when available, and recent
  working-set trend.
- Keep the existing Progress tab intact; this is a drill-down, not a second
  dashboard.

### 4. Watch resilience and transparency

- Improve the existing Watch status surface with explicit last sync and retry
  affordances where the current state already reports failure or stale sync.
- Do not redesign Watch workout execution or add simulator-only behavior.

## Explicit non-goals

- No social feed, community, trainer/video catalog, music preference system,
  client sharing, Pro tier, trials, paywalls, body-photo/measurement system,
  or multi-week coach plan.
- No simulator runs as part of this implementation.
- No DB++ upstream schema change unless a compatibility audit proves the new
  set semantics cannot remain app-side; the existing app model is the source
  of truth for this feature work.

## Verification and audit

- Add or update pure tests for set-kind round trips, superset/failure mapping,
  template start behavior, and progression presentation.
- Add smoke-contract assertions for the More → Saved Workouts route and the
  exercise progression drill-down.
- Run SwiftPM tests and repository guardrails only; do not run a simulator.
- Re-audit this document against the changed code and mark each item complete
  or document a concrete remaining gap before handoff.

## Implementation audit — 2026-09-18

All scoped items are complete:

- Saved Workouts is reachable from More, supports create/review/delete/start,
  and starts through the normal `EditablePlan` → live-workout boundary.
- `SetKind.failure` and `supersetGroup` are backward-compatible in the app
  plan model, Codable payloads, DB++ bridge, runtime prescription adapter, and
  live plan presentation. Legacy payloads default to working sets. The manual
  strength editor exposes all set kinds, including failure, and superset group
  controls.
- Exercise Info now opens a focused Exercise Progress drill-down with latest
  dated result, best available progression metric, session count, and a trend
  chart based on the existing repository trend calculation.
- Watch phone-sync failure now says Retry sync and keeps the last-sync state
  visible; it uses the existing sync path rather than adding a second protocol.
- The iPhone smoke contract covers the Saved Workouts route and the Exercise
  Info → Exercise Progress drill-down. Pure tests cover the new set semantics,
  legacy decoding, DB++ mapping, runtime materialization, and template start
  conversion.

Persona audit:

- Quick logger: the normal Today flow remains unchanged; Saved Workouts adds
  one-tap reuse without adding a primary tab.
- Structured strength lifter: set kinds, supersets, reusable sessions, and
  exercise progression now have explicit surfaces; the existing editor remains
  denser than a quick logger needs, so it stays secondary.
- Mixed cardio/strength user: Watch execution and sync status are unchanged in
  the fast path, with a clearer retry boundary when sync fails.
- Novice/bodyweight user: no new required setup, and the added progression view
  has a useful empty state instead of implying missing data is an error.
- Watch-first user: the feature work does not add simulator-only behavior or
  move execution controls away from the existing Watch surface.

Verification completed:

- `swift test --package-path CadenceCore`: 1,809 tests, 0 failures.
- Generic iOS device build with `CODE_SIGNING_ALLOWED=NO`: succeeded.
- `check-test-pyramid.sh`, `check-xcodebuild-platform.sh`, and `git diff --check`:
  passed.
- No simulator was run. The implementation is committed as `48b648b`; pushing
  is outside this request.
