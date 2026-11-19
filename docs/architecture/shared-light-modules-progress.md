# Shared module extraction progress

Work is committed locally on the existing PR branch. Do not push or update the remote PR until the owner authorizes publication.

| Phase | Implementation | Verification |
| --- | --- | --- |
| 1. Garmin portability | One Garmin bridge moved to CadencePortability; phone-only product link; existing FIT tests moved intact. Canonical mapping exposed with package access. | Manifest/Xcode boundary regression failed before extraction and passes after. Swift syntax and import boundary guards pass. Apple-platform FIT execution/builds remain unavailable on this Linux host. |
| 2. Widget contracts | CadenceFeatures is a dependency-free contract module; one shared runtime moved to CadenceWorkoutFeatures. ActivityKit identity and original localization bundle retained. | Real contract target builds on Linux; isolated tests compile the same sources through symlinks and pass (7 tests, including legacy JSON/deep-link fixtures). Widget dependency-closure regression passes. |
| 3. Shared workout / phone separation | New `CadencePhoneFeatures` target holds the 132 symbols never referenced from the Watch app target (dashboards, backup/export, assessment presentation, full plan editing, planning-draft editor, etc.). The remaining 88 symbols — Watch set-default parity, partner isolation, offline generation, durable HR outbox/sync — stay in `CadenceWorkoutFeatures`. `CadencePhoneFeatures` is linked into the phone `Cadence` target only; the Watch target's product list is unchanged from phase 2. | Reachability computed from actual Watch-app source text (filename-as-symbol, codebase's one-type-per-file convention), cross-checked that none of the 132 candidates are referenced anywhere under `Cadence Watch App Watch App` (incl. tests) and that no file kept in `CadenceWorkoutFeatures` references a moved symbol (no cycle). `swift package dump-package` boundary regression extended and passes; `swift -frontend -parse` run over all 656 touched/moved files with zero syntax errors (parse-only check — no Apple SDKs here, so this is not a type-check). `check-test-pyramid.sh` passes (two grandfathered 400-LOC files needed the new import; `ProgressView.swift` was fixed by inlining two one-line wrapper functions, a real shrink, not a whitespace trick). Apple-platform build/archive, widget/Live Activity rendering, and on-device Watch checks remain unverified here and stay release gates. |
| 4. Coaching isolation | Not started. Scoped: `VolumeCredit` (52 lines, `CadenceCore`) only calls `TrainingEngineBridge.setCredits`, a small DB++ credit lookup; the other ~1,300 lines of `TrainingEngineBridge.swift` are the plan-generation engine the research doc wants moved to a new `CadenceCoaching` target. The cut is splitting that lookup out so Core keeps a tiny credit adapter without re-creating a Core→Coaching→Core cycle. Not attempted yet — see the device checklist below for what has to hold once it lands. | N/A |

## Verification gap

Phases 1–3 above were verified only with Linux-side static/syntactic checks
(dependency-graph assertions via `swift package dump-package`, `swift
-frontend -parse` over every touched file, the symlink-isolated
`CadenceFeatures` build). None of it has gone through actual Xcode,
a simulator, or a device — this host has no Apple toolchain at all
(`swift build` on `CadenceCore` itself fails here because SwiftData has no
Linux implementation, which is pre-existing and unrelated to this work).

Two things are now prepared, not yet run, to close that gap on a Mac:

- `scripts/benchmark-module-extraction.sh --baseline 92bee3a4` — cold +
  incremental `xcodebuild -showBuildTimingSummary` for the `Cadence` and
  `Cadence Watch App` schemes, baseline vs HEAD, in disposable git
  worktrees/derived-data dirs (never touches the caller's working tree).
  This is the research doc's own acceptance bar: "no advertised speedup
  until measured." Dry-run tested end to end against a stub `xcodebuild`
  on this host (worktree creation/cleanup, both schemes, the touch-based
  incremental step) — a real run still needs a Mac.
- `docs/architecture/shared-light-modules-device-checklist.md` — the
  concrete owner-executable checklist per phase (Live Activity/widget
  behavior, Watch set-default parity and partner isolation, durable WC
  reconciliation, offline suggestion generation, 20-muscle volume
  accounting, citation rendering) plus a note that the existing
  `StoreMigrationRuntimeTests` old-store-upgrade coverage already exists
  and needs no new fixture for phases 1–3 (none of them touched a `@Model`
  type).

Persistent model definitions, schema membership and ActivityKit attributes must retain their defining modules. Every policy/mapping has one production definition. Apple-platform builds, FIT round trips, old-store upgrades, widgets/Live Activities, and offline Watch device checks remain release gates; static graph checks do not substitute for them.
