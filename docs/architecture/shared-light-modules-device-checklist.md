# Device/Xcode verification checklist — shared-light-modules extraction

Everything in `shared-light-modules-progress.md` was verified only with
Linux-side static/syntactic checks (dependency-graph assertions, `swift
-frontend -parse`, the symlink-isolated `CadenceFeatures` build). None of it
has run through Xcode, a simulator, or a device. This file is the concrete,
owner-executable checklist for closing that gap — do not mark any phase
below "device-verified" until it has actually been run, per this repo's
"device behavior is the acceptance target" rule.

## 0. Prerequisite: build-time benchmark (phases 1–4, research doc's own
   acceptance bar — "no advertised speedup until measured")

```
scripts/benchmark-module-extraction.sh --baseline 92bee3a4
```

`92bee3a4` is the commit this extraction started from (tip of PR #778 before
phase 1). Run on a Mac with Xcode. Produces cold + incremental build timing
and a `-showBuildTimingSummary` compiler-task breakdown for both the
`Cadence` and `Cadence Watch App` schemes, before vs after. Record the
summary table in the PR description.

## 1. Garmin FIT extraction (phase 1)

- [ ] Archive-build the `Cadence` scheme; confirm `FreeExerciseDBPlusPlusFIT`
      still links (phone needs it) and the Watch build has no FIT SDK task.
- [ ] Device: export a completed strength workout to Garmin FIT from
      Settings → Garmin, re-import it, confirm duplicate keep/replace/
      cancel/undo all behave exactly as before this branch.
- [ ] Device: attempt an oversized/malformed FIT file import; confirm the
      same error copy as before the extraction.

## 2. Widget/platform-contract extraction (phase 2)

- [ ] Device: start a strength workout, confirm the Lock Screen / Dynamic
      Island Live Activity starts, updates, and its actions still work.
- [ ] Device: background the app mid-set; confirm the Home Screen widget and
      the Watch complication both still reflect the active workout.
- [ ] Device: tap the widget/complication deep link; confirm it opens to the
      same place as before.
- [ ] Device: open the Smart Stack rest-ring widget during a rest timer.
- [ ] Confirm no regression in golden decode/encode of existing app-group
      snapshots/commands (suite + key strings, stale-marker rules) —
      `CadencePlatformTests` already covers this at the unit level; this
      step is the live on-device confirmation.

## 3. Shared workout / phone-feature split (phase 3)

- [ ] Device, Watch: set-default parity — log a set on the phone, confirm
      the Watch proposes the same next-set defaults (weight/reps) it did
      before this branch, including performer-specific defaults in a
      partner session.
- [ ] Device, Watch: partner session — confirm partner rotation and
      per-performer isolation (set history, defaults) are unchanged.
- [ ] Device, Watch: pause a strength session, kill the Watch app, relaunch;
      confirm the session recovers exactly as before (`ActiveSessionRecovery`
      is phone-side now — confirm the Watch's own resumable-session path,
      which stayed in `CadenceWorkoutFeatures`, is what actually fires).
- [ ] Device: complete a Watch-recorded set with live HR; confirm the
      phone's post-workout HR chart renders identically.
- [ ] Device: force a WatchConnectivity drop mid-sync (airplane mode toggle),
      confirm durable completion reconciliation still delivers the session
      once connectivity returns, with no duplicate or dropped sets.
- [ ] Old-store upgrade: `CadenceCoreTests/StoreMigrationRuntimeTests` already
      exercises legacy `default.store` → split `Local.store`/`Sync.store`
      migration end-to-end; confirm it still passes under `swift test`
      (requires macOS/SwiftData — cannot run on Linux). No new fixture is
      needed for phase 3; this phase touched no `@Model` types.

## 4. Coaching/catalog isolation (phase 4 — not yet started)

Before any device check applies here, the code move itself has to happen:
split `TrainingEngineBridge.swift`'s small DB++ credit lookup (what
`VolumeCredit` actually calls) from its ~1,300 lines of plan-generation engine,
keeping the former in `CadenceCore` and moving the latter to a new
`CadenceCoaching` target consumed by both phone and Watch. Once that lands:

- [ ] Device, Watch, airplane mode: request a single-exercise suggestion with
      no phone reachable; confirm it still generates from
      `ExerciseLibrary.starter` with the same exercise choice and citation
      as before.
- [ ] Device: confirm every coach recommendation still renders its "The
      Science" citation link (`CitationRegistry`/`CoachSourcesLink`) —
      `pellandDoseResponse2026` for volume credit specifically.
- [ ] Device: confirm 20-muscle-group weekly volume accounting (Progress →
      muscle heatmap) matches pre-extraction numbers for an identical
      logged week.
- [ ] Device: confirm canonical exercise IDs/aliases/exclusions still
      resolve the same exercises (spot-check a few aliased/excluded
      exercises used in existing saved workouts).
- [ ] Re-run the step-0 benchmark against the phase-4 commit specifically,
      since this is the phase the research doc expects to move the needle.
