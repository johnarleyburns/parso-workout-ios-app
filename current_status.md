# Current Status

Updated: 2026-08-28

## Active plan — 2026-08-27 field-test remediation (planning complete)

**Plan:** `docs/field-test-batch-2026-08-27/` (`00-overview.md` plus one phase
file per reported issue). Nine phases are queued, one phase and one local commit
per issue. **Do not push until the user explicitly gives the go-ahead.**

### Immediate next task

Phase 4: restore iPhone Other Cardio live-HR reconnect. Read
`04-phase4-watch-hr-reconnect.md` before changing watch HR transport.

### Efficient remaining work groups

The remaining issues are best delivered as three focused workstreams while
retaining one phase-specific local commit per issue:

1. **Watch HR transport — Phase 4.** Finish the cross-app command/relay
   lifecycle first; it is independent of the display work and needs both smoke
   gates plus one hardware pass.
2. **Watch cardio experience — Phases 6 → 7.** Implement the shared live-metric
   presenter and explicit HR/GPS state in Phase 6, then reuse that state and the
   Phase 3 envelope for the conditional HR graph/summary in Phase 7. Run the
   watch smoke once after each phase and combine hardware verification for both
   displays where practical.
3. **History flow — Phases 8 → 9.** Complete Back plus edit Save/Cancel in
   Phase 8, then add Home Show more in Phase 9 and verify the end-to-end route in
   one iPhone smoke pass. Phase 9 should not start before Phase 8 because its
   acceptance flow depends on the history-detail Back action.

Hardware field-test backlog: Phase 3 sync, Phase 4 HR reconnect, and Phases 6–7
watch display behavior remain unverified on real hardware. Do not push until
the user explicitly authorizes it.

### Phase queue

| phase | status | field-test outcome |
|---|---|---|
| 1 | DONE | Add Set cycles through performers instead of resetting to Me |
| 2 | DONE | exercise search has no per-character multi-second stalls |
| 3 | DONE | completed watch cardio reliably syncs once to iPhone |
| 4 | DONE | iPhone Other Cardio reconnects to watch live HR |
| 5 | DONE | Connect HR has Cancel back to Home with sensor cleanup |
| 6 | DONE | watch live cardio layout: time, conditional zone HR, GPS-only distance |
| 7 | NEXT | watch summary conditionally shows HR graph, max, and average |
| 8 | pending | workout edit has large Save/Cancel; history detail has Back |
| 9 | pending | Home Completed Workouts has Show more… to full History |

### Batch execution and verification

- Implement the queued phases in grouped commits, run their required unit/smoke
  gates, and update this status after each grouped delivery.
- Run `make ci` for every phase; run `make smoke` for iPhone UI phases and
  `make watch-smoke` for watch phases as specified by the overview.
- Adjust the existing iPhone/watch smoke test functions rather than increasing
  their test-function count.
- Keep unrelated working-tree changes out of phase commits. Preserve this
  status file as uncommitted if the existing status-file convention still
  applies when implementation begins.
- Hardware verification is still required for watch sync, watch HR connection,
  and both watch cardio display phases.
- Phases 1, 2, 3, and 5 are implemented and committed locally. No batch commit
  has been pushed. The next implementation is Phase 4, followed by the grouped
  workstreams above.

### Phase 1 — DONE (rotate Add Set through performers)

- `SetAlternation.nextPerformerID` now advances from the last working set on the
  current exercise before considering pending prescription rows. This means Me →
  partner, partner → next partner, and last performer → Me, all using the
  persisted roster order and wrapping cyclically.
- The resolver now receives an explicit `hasLoggedWorkingSet` signal so an owner
  set (`nil`) is distinct from no prior set. Empty rosters are safe, and a
  removed last performer falls back to the first valid configured performer.
- Updated the existing iPhone smoke test to assert that Add Set opens on Sam
  after Me saves, while still verifying that switching performers changes the
  per-performer history card.

Verification:

- `swift test --filter SetAlternationTests`: **13 passed, 0 failures**.
- `make ci`: **1,656 tests passed, 0 failures**; test-pyramid, no-network, and
  citation guardrails passed.
- `make smoke`: **passed**, 1 iPhone UI test, 0 failures, 251.2s. The first
  attempt exposed the pre-existing smoke assertion that expected the old
  owner-first behavior; the assertion was updated and the rerun passed. The
  simulator emitted the known no-iCloud/no-pairing and debugger-version
  warnings.
- Hardware partner-session verification remains outstanding.

### Phase 2 — DONE (responsive exercise search)

- Reused the normalized built-in exercise index for best-match ranking instead of
  constructing a new index for every debounced query.
- Cached normalized names and exact built-in names so query handling does not
  refold or rescan the full catalog for the remaining match checks.
- Preserved exact-match creation, best-match suggestions, and the existing
  search/browse/swap flows.

Verification:

- Existing `ExerciseSearchIndexTests` remain the deterministic ranking and
  performance regression coverage; the existing iPhone picker smoke flow covers
  typing and selecting a result.
- Full grouped commit verification passed: 1,656 unit tests, iPhone smoke, and
  watch smoke; all repository guardrails passed.

Phase 3 was completed in commit `d789d2b`; see its verification and hardware
backlog below.

### Phase 3 — DONE (durable watch cardio completion sync)

- Added a versioned `WatchCardioCompletion` envelope with a stable app workout
  UUID, cardio type/title, start/end, HR summary/samples, and GPS-gated distance.
- Watch Save now persists the completion in a UserDefaults queue before ending
  HealthKit, sends it with durable `transferUserInfo`, retries on activation,
  and removes it only after an iPhone acknowledgement. The summary reports
  pending/syncing state.
- iPhone decodes completions from message and user-info paths, ingests
  transactionally, refreshes Home/History, and acknowledges new and duplicate
  records. Later HealthKit imports reconcile by stable ID or matching timing.
- Added codec/version, GPS gating, duplicate delivery, and HealthKit
  reconciliation tests.

Verification:

- `make ci`: **1,660 tests passed, 0 failures**; all guardrails passed.
- `make watch-smoke`: **9 watch unit tests passed, 0 failures**; watch build and
  existing watch UI smoke passed.
- Hardware verification remains required: complete cardio on a real watch while
  the phone is backgrounded/relaunched, then confirm one iPhone record.

Next: Phase 4 — read `docs/field-test-batch-2026-08-27/04-phase4-watch-hr-reconnect.md`
before changing watch HR reconnect. After Phase 4, continue with the grouped
watch-cardio phases 6 → 7, then history phases 8 → 9.

### Phase 5 — DONE (cancel Connect HR back to Home)

- Added an always-available Cancel action to the Connect Heart Rate view.
- Cancellation stops any pending watch workout/relay and returns to Home without
  starting or saving cardio.
- Extended the existing iPhone smoke flow to verify the Cancel control is
  available while the HR gate is active.

Verification:

- The grouped commit `fadf1a9` passed 1,656 unit tests, all guardrails, iPhone
  smoke, and watch smoke.
- Hardware HR cancellation/reconnect verification remains outstanding.

### Phase 4 — DONE (restore iPhone cardio connection to watch HR)

- iPhone starts WCSession before issuing a watch-HR request and holds a start
  tapped during activation until the session reports its installed companion.
- Every start is sent through both immediate messaging and durable
  `transferUserInfo`; the watch routes both deliveries through one handler and
  returns the same request ID, including for an immediate/queued duplicate.
- The phone accepts the durable-path acknowledgement, while request-scoped
  samples continue to reject stale or unrelated sessions. Existing stale
  `.alreadyActive` stop/retry and cancellation cleanup remain bounded.
- Added a watch unit regression for duplicate immediate/queued start delivery.

Verification:

- `make test`: **1,660 tests passed, 0 failures**; all repository guardrails
  passed.
- `make smoke`: **passed**, 1 iPhone unit/UI smoke test, 0 failures, 261.9s.
- `make watch-smoke`: **passed**, 10 watch unit tests and 1 watch UI smoke
  test, 0 failures.
- Generic iOS build-for-testing was also attempted but remains blocked by the
  existing missing development-team signing configuration for `CadenceTests`
  and `CadenceUITests`; the pinned simulator smoke build/test succeeded.
- Hardware verification remains required: test Other Cardio from a cold launch
  and after a prior workout ends, then verify live BPM/zone and failure-state
  recovery on a real watch.

Next: Phase 7 — read `docs/field-test-batch-2026-08-27/07-phase7-watch-cardio-hr-summary.md`
before changing the watch cardio summary.

### Phase 6 — DONE (refine watch cardio live metrics)

- Added the pure `WatchCardioLivePresenter` with elapsed-time text, optional
  zone-colored BPM, GPS-gated compact distance, and the existing iPhone HR-zone
  boundaries. HR and GPS capability now come from explicit workout session
  configuration rather than transient sample values.
- Reduced the live cardio screen to elapsed time, optional BPM, and optional
  lower-left distance while preserving the separate pause/resume/end controls
  and their accessibility behavior. Distance remains visible as `0 m` for an
  enabled GPS session and is hidden for non-GPS sessions.
- Added presenter tests for every zone boundary, HR/GPS visibility, nil/zero
  samples, metric/imperial formatting, and elapsed time.

Verification:

- `make ci`: **1,664 tests passed, 0 failures**; all repository guardrails
  passed after keeping `WatchWorkoutManager.swift` within its 400-line limit.
- `make watch-smoke`: **10 watch unit tests and 1 watch UI smoke test passed,
  0 failures**. The simulator emitted the known missing debugger-version
  warning; the gate completed successfully.
- Hardware verification remains required: check small/large-watch legibility,
  truncation, zone transitions, and GPS-only distance on a real watch.

Next: Phase 7 — read `docs/field-test-batch-2026-08-27/07-phase7-watch-cardio-hr-summary.md`
before changing the watch cardio summary.

## Active plan — Exercise DB++ adoption

**Plan:** `plans/exercise-db-plusplus/2026-08-23/` (10 files: `00-overview.md`,
`decisions.md`, and one file per phase `01`–`08`). The plan is written to be
implementable without further research: every table, mapping, signature and test
name it needs is already in it.

**Plan status: phases 1-9 are implemented, verified and pushed to `main`.
The current working tree contains the follow-up watch reliability and partner
ordering work described below; this file remains intentionally uncommitted.**

Start at **Immediate next task**, not at the top.

### What this work does

1. Replace the `yuhonas/free-exercise-db` upstream with
   `johnarleyburns/free-exercise-db-plusplus` (DB++) — an evidence-audited
   annotation layer that preserves every upstream record byte-identically inside
   `source` and adds movement classification, direct/indirect/stabilizer muscle
   roles, volume eligibility, per-pattern literature references, and a normalized
   20-muscle ontology. Unlicense, same as upstream. Imagery is unaffected: the
   873 exercise ids are the same set as the 873 bundled `ExerciseImages/<id>/`
   directories.
2. Delete the 8-part `BodyPart` simplification **and** the 21-entry
   `MuscleCatalog`, replacing both with one `MuscleGroup` type whose raw values
   are DB++'s ontology strings.
3. Rebuild weekly volume on DB++'s published set credits — direct 1.0, indirect
   0.5, stabilizer 0.0, and nothing at all from movements DB++ marks
   non-volume-eligible.
4. Home `This Week`: delete the `Muscles` row and its expanded section; the
   `Volume` row and list now carry the per-muscle-group content.
5. Suggested workouts: drop the minimum/medium/maximal tiers for one minimum
   target (4 sets per tracked group, 20-set cap) rendered in five **training
   styles** — Fitness, Bodyweight, Powerlifting, Olympic Weightlifting,
   Strongman.
6. Surface the movement evidence: 60 DB++ references and 89 pattern summaries
   become tappable citations behind every muscle-role claim.
7. Replace the swap picker's free-text search with a DB++ similarity ranking
   (phase 9, added 2026-08-24).

## Active follow-up — watch reliability and partner-first plans

The user reported three related regressions/needs on 2026-08-24. The work is
broken into small, independently verifiable phases so the behavior can be
field-tested on a real watch.

### Phase 10 — DONE (watch background session capabilities and audio)

- Added the watch `audio` background mode alongside `workout-processing`.
- Fixed the archive normalization step: it previously deleted
  `UIBackgroundModes` wholesale, which silently disabled both background HR
  delivery and short workout audio in TestFlight builds. It now preserves only
  `audio` and `workout-processing`.
- Boxing/interval view no longer stops an active HealthKit workout merely because
  SwiftUI removes the view while the app enters the background.
- Bell resources were verified in the built watch bundle; the resource lookup
  was not the cause of the silence.

### Phase 11 — DONE (live HR on every boxing phase)

- The interval metric strip now always renders an explicit heart-rate value (or
  `--`) on work, warning, rest and transition states, with a visible heart icon.
- Strength rest now shows the same live BPM value.
- Apple’s documented behavior is: an active `HKWorkoutSession` continues to
  receive sensor data in the background, and short clips may play in the
  background while that session is active. If the user backgrounds the app
  without an active workout session, continuous watch HR is not available to
  this app; the system workout session is the supported route.

### Phase 12 — DONE (persist partner-first performer order)

- Plan editor roster order now respects a partner moved before “Me” instead of
  rebuilding the resolver roster as owner-first.
- The materialized session and live set editor use the persisted roster order.
- A session with no logged sets now defaults to the first configured performer,
  so a partner-first plan preloads the partner rather than “Me”.

### Phase 13 — DONE (verification)

- `make ci`: **1,652 tests passed**, pyramid/no-network/citation guardrails green.
- `make smoke`: iPhone smoke passed.
- `make watch-smoke`: 9 watch unit tests and the existing watch UI smoke passed.
- Remaining requirement: field-test boxing audio/background HR on hardware and
  create a partner-first custom plan, then start it and verify the first set.

### Repository position

- Branch: `main`. Exercise DB++ phases 1-9 and their follow-up commits are
  pushed. The current watch follow-up remains in the working tree until its
  hardware field test is complete.
- `current_status.md` stays uncommitted, by instruction.
- The working tree contains the watch follow-up files listed in phases 10-13
  plus this status file.
- The latest functional commit is `0a4c593`
  (`feat: rank similar exercises for resistance swaps`).

| commit | phase | what |
|---|---|---|
| `815b8e2` | — | plan docs (`plans/exercise-db-plusplus/2026-08-23/`, force-added: `plans/` is gitignored) |
| `6cdae29` | 1 | vendor the DB++ snapshot + `ExerciseDatabase` decoder |
| `f95e968` | 2 | the `MuscleGroup` ontology |
| `53a1b68` | 3 | annotation pipeline, `Exercise` schema, seeding, export |
| `e63c086` | 4 | weekly volume on `VolumeCredit` |
| `40115b0` | — | UI-test helper: scroll both ways (pre-existing red gate on `main`) |
| `3bf4794` | 5 | Home `This Week` — Volume carries the muscle groups |
| `f996e85` | 7 | suggested workouts: one target, five training styles |
| `e869bc3` | 6 | replace `BodyPart` with `MuscleGroup` |
| `0f71083` | 8 | cite DB++ movement evidence |
| `0a4c593` | 9 | rank similar exercises for swaps |

Test count is now **1,652**, all green.

### Execution protocol for this plan (differs from the CLAUDE.md default)

Per the request that opened this work:

1. Read this file before starting a phase; continue from **Next task** below.
2. Implement exactly one phase.
3. Verify: `make ci` always; `make smoke` for any phase the plan marks UI-touching
   (5, 6, 7, 8); `make watch-smoke` additionally for phase 6.
4. Update this file: what shipped, test counts, deviations, next phase.
5. Commit the phase, staging everything **except `current_status.md`**.
6. Push after the functional phase commits when the user has authorized it;
   leave `current_status.md` uncommitted.

## Phase 1 — DONE (vendor the DB++ snapshot and decode it)

Shipped:

- `CadenceCore/Sources/CadenceCore/Resources/free-exercise-db-plusplus.json`
  (1.8 MB, schema 0.3.0, converter 0.8.0, generated 2026-08-24, 873 exercises)
  plus its Unlicense text. `free-exercise-db.json` / `.LICENSE` deleted.
- `ExerciseDatabase.swift` — decodes the whole document: metadata, set credits,
  60 evidence references, 89 pattern summaries, and all 873 records with their
  classification, annotation and verbatim `source`. Records are sorted by
  `exerciseId` because `exercises` is a JSON object and decode order is undefined.
- `ImportedExerciseLibrary` now reads `ExerciseDatabase.Record.source` and is
  otherwise untouched. It deliberately does **not** consume the annotation layer
  yet — that is phase 3 — which is what makes this phase behaviour-neutral.
- `ExerciseLibrary.exerciseAnnotationRepoURL` added (displayed in phase 8).
- `scripts/validate-exercise-db.py` (new) + `scripts/update-exercises.sh` rewired:
  a refresh is now rejected unless completeness is `full`, the count matches
  `outputExerciseCount`, the 20-muscle ontology is unchanged, every annotated
  muscle is in-ontology, `volumeEligible` agrees with a non-empty `direct` list,
  and every `pattern:` evidence ref resolves.
- `scripts/build-exercise-images.sh` reads the new layout; `COMMIT=b0eed06` stays
  because DB++'s `source` is that same upstream data.
- `Package.swift` and `CadenceCore/CREDITS.md` updated.

Verification:

- `make ci`: build clean, **1,568 tests passed, 0 failures**, test-pyramid and
  no-network guardrails OK. (1,553 before this phase + 15 new. The "1,329" figure
  recorded in an earlier handoff was stale.)
- `xcodebuild -scheme Cadence ... build`: **BUILD SUCCEEDED**, no warnings.
- `python3 scripts/validate-exercise-db.py` on the vendored snapshot: OK,
  873 exercises, 673 volume-eligible.
- The phase's own acceptance test: `ImportedExerciseLibraryBaselineTests` compares
  20 templates spread across the alphabetically sorted catalog against values
  captured from the build **immediately before** the swap, and asserts the count
  and the ordering. All existing `ImportedExerciseLibraryTests` pass unmodified.

Deviations from the plan: none. The plan anticipated the validation being inline
in `update-exercises.sh`; it went into `scripts/validate-exercise-db.py` instead so
the same checks can be run directly against the vendored file, which the new test
suite and CREDITS both reference.

## Phase 2 — DONE (the `MuscleGroup` ontology)

Shipped `CadenceCore/Sources/CadenceCore/MuscleGroup.swift`: a 20-case enum whose
raw values are DB++'s ontology strings verbatim, with display names, scientific
names, colloquial synonyms (which absorb the retired `obliques` / `upper chest` /
`front delts` / `rear delts` / `rhomboids` search terms), a grouping-only
`region`, the descending-mass tie-break order, the 13-group `defaultTracked` set,
`canonical(_:)` / `canonicalize(_:)` covering every retired id and upstream
spelling, and `defaults(forCategory:)`.

Verification: `make ci` green — **1,584 tests, 0 failures** (1,568 + 16 new),
guardrails OK.

Two tests carry the weight:

- `testRawValuesMatchDatabaseOntology` pins the enum to
  `ExerciseDatabase.muscleOntology`, so a refresh that renames a muscle fails the
  build rather than creating an unreachable dimension.
- `testDefaultTrackedGroupsAllHaveDirectExercises` proves every tracked group has
  at least one volume-eligible movement that trains it directly, and asserts
  `tibialis` still has none. That is the check that justifies D4.

**Deviation from the plan.** `02-muscle-group-ontology.md` had this phase also
convert `MuscleCatalog` into a forwarding shim and delete the `Muscle` struct.
That is not behaviour-neutral: `MuscleCatalog.all` feeds Home's muscle rows and
the suggested-workout muscle space, both of which are still keyed by the retired
ids until phase 4, so flipping `all` from 21 fine muscles to 20 groups mid-phase
would have shown every muscle at zero sets and starved the generator of
candidates. `MuscleCatalog` and `Muscle` are therefore left completely untouched;
they are deleted in phase 6 together with their consumers and `BodyPart`.
`MuscleGroup` is unused by production code until phase 3, by design.

Also deferred to phase 6 for the same reason: extracting
`MuscleCatalog.canonicalName` into `ExerciseNameCanonicalizer` (a pure rename with
call-site churn in `CoachSession` and `CoachFacts`, no value until those files
move).

## Phase 3 — DONE (annotation pipeline, `Exercise` schema, seeding, export)

The first phase that changes what the app actually knows about an exercise.

Shipped:

- `ExerciseTrainingType` / `ExerciseModality` / `ExerciseSportContext` /
  `AnnotationConfidence` in `ExerciseTaxonomy.swift`, all decoding leniently so a
  future DB++ schema revision drops unknown values instead of failing.
- `VolumeCredit` — the single place a working set becomes weekly volume. Direct
  1.0, indirect 0.5, stabilizer 0.0, read from the vendored document rather than
  hard-coded, and **nothing at all** from a movement DB++ marks non-volume-eligible.
- `ExerciseTemplate` and `Exercise` carry `directMuscles` / `indirectMuscles` /
  `stabilizerMuscles` / `volumeEligible` / `trainingTypes` / `modalities` /
  `sportContexts` / `movementPatternIDs` / `annotationConfidence` /
  `sourceExerciseID`. Every `Exercise` field is optional or defaulted.
- `ImportedExerciseLibrary` consumes the annotation; its hand-written `muscleMap`
  is deleted. Non-volume movements keep their upstream muscles so they stay
  browsable, and simply earn no credit.
- **The curated catalog reversal**: where a curated entry resolves to a database
  record, the DB++ annotation now wins for muscle roles, volume eligibility and
  classification. The comment at `ExerciseLibrary.starter` records the reversal
  and why. Curated-only entries keep their hand mapping and carry
  `annotationConfidence == nil`, which phase 8 surfaces rather than implying
  evidence that does not exist.
- Seeding (`seedVersion` 8 → 9): `canonicalizeStoredMuscleIDs` rewrites legacy ids
  on built-in **and custom** rows after parking the originals in the legacy
  `muscleGroups` tag field; `applyAnnotation` refreshes the annotation
  unconditionally but only touches `updatedAt` when something changed, so a second
  seed is a no-op.
- Export **v6**: ten new optional fields; v1-v5 files import exactly as before and
  have their muscle ids canonicalized on the way in.
- `MovementPattern.init?(databasePatternID:)` maps 60+ DB++ patterns onto our
  coarse vocabulary and is consulted before the name heuristic. Single-joint
  patterns deliberately return nil and fall through to the heuristic.

### What the data actually changed

**729 of the 873 imported templates got different muscle roles.** Spot checks now
pinned in `ImportedExerciseLibraryBaselineTests`:

- `Power Snatch` was primary **hamstrings**; it is quadriceps + glutes + traps.
- `Seated Head Harness Neck Resistance` was **traps**, because the old catalog had
  no neck to map upstream `neck` onto. DB++ does.
- `Floor Press` was primary **triceps** only; the chest is a prime mover.
- `Dumbbell Lunges` credited hamstrings and calves as secondary work. They
  stabilise, so they no longer earn half a set each.
- A deadlift no longer credits the lower back at all.

### Verification

- `make ci`: build clean, **1,612 tests passed, 0 failures** (1,584 + 28 new),
  guardrails OK.
- `xcodebuild -scheme Cadence build`: **BUILD SUCCEEDED**, no warnings.
- 20 existing tests needed updated **expectations** (never weakened assertions);
  each was checked against the DB++ annotation first. The interesting one:
  `CoachPlanOptimizerTests.testVarietyRotationKeepsAResolvedLoad` used to see a
  curl on both planned days. Rows credit the biceps indirectly now, so the coach
  correctly stops double-dosing them and rotates a row variant instead; the test
  was re-pointed at the rotation that actually happens rather than relaxed.

### Deviations from the plan

1. **`VolumeCredit` landed here, not in phase 4.** `ExerciseTemplate.volumeCredits`
   needs it, and having two credit implementations for one phase was worse than
   moving the type early.
2. **`MuscleCatalog` was rebased onto `MuscleGroup` here, not deferred to phase 6.**
   Phase 2 deliberately left it alone; that could not survive phase 3. Once stored
   ids became canonical, `MuscleCatalog.muscle(id)` rejected every one of them, and
   `TrainingFacts`, the suggested-workout muscle space, `BodyPart.part(forMuscleID:)`
   and the Home muscle rows all silently tallied zero. `Muscle` is now a display
   record over a `MuscleGroup` and the catalog is `MuscleGroup.canonicalOrder`.
   **Lesson for the remaining phases: a vocabulary switch and its consumers have to
   land in the same commit.**
3. `MuscleCatalog.canonicalName` (exercise-name matching, unrelated to muscles) is
   still there; extracting it stays a phase 6 chore.

### Required before the next TestFlight build

A **CloudKit Production schema deploy** in the Dashboard, for the ten new
`Exercise` fields (decision D12). Additive and nullable, so no destructive
migration — but the production schema still has to learn about them.

## Phase 4 — DONE (weekly volume accounting on the new ontology)

Shipped:

- `TrainingFacts` now carries `weeklySetsByGroup`, `frequencyByGroup` and
  `volumeTrendByGroup` as the source of truth. `weeklySetsByMuscle` is derived from
  them; `weeklySetsByPart`, `frequencyByPart` and `volumeTrendByPart` are
  transitional rollups so the optimizer and rules are untouched until phase 6.
- Every weekly tally routes through `VolumeCredit`, including the prior-week loop
  that feeds the trend. Stretching, plyometrics and cardio now credit **nothing**;
  a muscle that only stabilises credits **nothing**.
- The body-part rollup credits a part **once per set at its best member credit**,
  which reproduces the old primary/secondary semantics exactly — a squat hitting
  three leg groups is still one set of legs.
- `PlanAwareWeeklyAccounting` gained group-keyed twins and resolves a planned
  recommendation to a catalog template first, so planned volume uses the same
  roles and eligibility as completed volume.
- `VolumeLandmarks` has MEV/MAV/MRV bands for all 20 groups; the `BodyPart`
  overload takes the widest member band so a part holding a large muscle is not
  judged against a small one's ceiling.
- `CoachSchedulePreferences.trackedMuscleGroups` (default: the 13). A user who
  opted a body part out of coverage before the adoption keeps that opt-out —
  every group belonging to it drops out of the tracked set on decode.
- `BodyPart.guessCategory(from:)` moved to `ExerciseCategory.guess(fromName:)`
  with a forwarder left behind.

Verification: `make ci` green — **1,629 tests, 0 failures** (1,612 + 17 new),
guardrails OK; `xcodebuild -scheme Cadence build` **BUILD SUCCEEDED**. No
existing test needed changing beyond disambiguating `.chest` between `BodyPart`
and `MuscleGroup` in `VolumeLandmarksTests`.

**Deviation:** none of substance. `VolumeCredit` had already landed in phase 3, so
§1 of the phase file was already done.

**New standing note — a stale SwiftPM incremental build can crash the test
binary.** After changing `Exercise`'s initializer signature, `swift test` first
failed to link (`Undefined symbols … Exercise.__allocating_init`) and then, after a
partial `swift package clean`, died with `signal code 11` inside XCTest's own
teardown (`-[XCTest _internalBaseClassCleanup]`), which looks like a code crash
but is not. `rm -rf CadenceCore/.build && swift build && swift test` cleared it.
Reach for a full clean whenever a crash lands in XCTest internals rather than in
our frames.

## Phase 5 — DONE (Home's This Week card)

The change you actually asked for is now on screen.

- The `Muscles` progress row and the whole expanded `Muscles` section are
  **deleted**. `This Week` has three progress rows: Strength, Cardio, Volume.
- `Volume` carries what `Muscles` used to: one row per `MuscleGroup`, on the same
  4 / 8 / 12-set scale, with the richer layout (name, bar, sets, band text).
- `HomeDashboardState.MuscleRow` is gone; `VolumeRow` is keyed by `MuscleGroup`
  and carries `scientificName` and `isTracked`.
- Rows shown = the 13 tracked groups always, plus any untracked group the user has
  actually trained. An untracked row is prefixed with a dashed circle, greyed, and
  carries the VoiceOver hint "Not a tracked muscle group".
- `volumeCoverage` averages **tracked rows only**, so half a set of incidental
  neck work cannot drag the headline number down.
- Identifiers: `home.volume.<group.rawValue>` (e.g. `home.volume.quadriceps`,
  `home.volume.lower_back`). `home.week.muscles`, `home.week.musclesHeading` and
  `home.muscle.*` are gone, and the smoke test asserts positively that they are.
- Second citation added under the list: the direct/indirect/stabiliser split is a
  science claim on screen, so it resolves `pellandDoseResponse2026` through
  `CitationRegistry` and renders with `CitationLink`.
- `WeekVolumePresenter` (Your Plan) re-keyed onto `MuscleGroup`, with
  `VolumeLandmarkBar` and `CoachPartVolumeSection` following.
- **Deleted `HomeWeeklyVolumeSection.swift`** — dead code, nothing constructed it
  since `HomeWeekDashboardSection` took over.

Verification: `make ci` green (**1,631 tests, 0 failures**, guardrails OK),
`xcodebuild -scheme Cadence build` succeeded, `make smoke` passed.

**A second UI-test-helper fix was needed.** Removing a progress row makes Home
shorter, which moved `home.startWorkout` to y=153 — fully visible, but inside the
167.8pt top scroll-edge glass gradient, and at that scroll position neither
swiping up nor down frees it. XCUITest refuses to tap an element whose hit point
falls under an overlay; a real finger is unaffected, because the gradient has no
touch handling. `scrollToHittableAndTap` now ends with a coordinate tap on the
element's own centre, reached only when the element exists and scrolling cannot
free it, so it cannot mask a missing control.

## RESOLVED — the iPhone smoke gate (was red on `main`)

`make smoke` failed at `SmokeLaunchTests.swift:172` on `b818f26` with no source
changes at all, reproduced three times including on a freshly erased simulator.
Root cause and fix:

- `1a89d08` replaced the suggested-workout sheet's Close tap with
  `app.navigationBars["View Suggested Workout"].swipeDown()`. That leaves Home at a
  scroll offset where `home.startWorkout` sits at y=153, **under the top
  scroll-edge glass band** (`AdditionalDimmingOverlay`, {{0,0},{393,167.8}}).
- `XCUIApplication.scrollToHittableAndTap` only ever swiped **up**, which pushes
  the button further under the band. Eight swipes and sixteen seconds later it was
  still not hittable, and the fallback `el.tap()` failed with hit point `{-1,-1}`.
- Fix: the helper now swipes up, then **down**, before falling back to a direct
  tap. `make smoke` passes (1 test, 0 failures, 259s).

**It is a test-helper limitation, not a product bug.** The glass edge effect is a
visual overlay a real finger scrolls past; only XCUITest treats it as an
obstruction. Nothing in the app changed.

## Phase 7 — DONE (suggested workouts: one target, five training styles)

Taken ahead of Phase 6, which it does not actually depend on.

- `SuggestedWorkoutTier` is **deleted**. `SuggestedWorkoutStyle` ships five cases:
  `fitness`, `bodyweight`, `powerlifting`, `olympic`, `strongman`.
- One target for every style — **4 sets per tracked muscle group**, one **20
  planned-set cap** (`suggestedWorkoutTargetSetsPerGroup` /
  `suggestedWorkoutPlannedSetCap`). The old 4/8/12 × 20/30/40 tiers were the same
  greedy ordering at three lengths; what varies now is the movements.
- Style membership comes off the DB++ annotation, on
  `SuggestedExerciseCandidate.matches(_:)`: fitness = strength ∧ general-fitness
  only, bodyweight = `modalities.contains(.bodyweight)`, and the three sports off
  `trainingTypes`.
- **Style biases, it never filters** (NFR-8). `solve` runs two passes over one
  index: pass 1 restricted to the style's pool, pass 2 over everything, and only
  for gaps pass 1 could not close. `isBetter` breaks an exact tie toward the
  in-style movement, so the alphabetical tie-break cannot beat style membership.
- The borrowing is **disclosed, not hidden**: `SuggestedWorkoutOption.
  inStyleExerciseCount` drives subtitle text — "all olympic weightlifting
  movements" or "1 of 3 olympic weightlifting movements".
- Volume-ineligible movements are dropped at index construction, so a stretch can
  never be prescribed as strength work whatever muscles it lists.
- Deficits are computed over `input.trackedGroups` only (wired from
  `settings.coachSchedulePreferences.trackedMuscleGroups`).
- Chooser and About sheet rewritten: `chooserIntro`, `choosingAPlan`, 7
  `aboutSteps` and 6 `pseudocode` lines that state the two passes, the credit
  split and the cap. The About sheet also lists what each style is. Both citation
  sets still resolve through `CitationRegistry`; no raw ids on screen.
- Identifiers: `suggestedWorkout.style.<rawValue>` and
  `suggestedWorkout.about.style.<rawValue>`. The signpost is now
  `allStylesGeneration`.

### Verification

`make ci` green (**1,652 tests, 0 failures**, guardrails OK), `make smoke` passed
(1 test, 273s). Measured on the full shipped catalog: vector index **12.8 ms**
median, five-style solve **3.0 ms** median — the five-style solve is *faster* than
the old three-tier one, because the index no longer carries the ~140
volume-ineligible movements.

The smoke test asserts positively that `suggestedWorkout.minimum` is gone.

## Phase 6 — DONE (coach, picker, watch; `BodyPart` deleted)

**All the code is written and the three required gates are green.**

### Shipped in the working tree (76 files changed, 2 added, 2 deleted)

- **`BodyPart.swift`, `Muscle` and `MuscleCatalog` are deleted.** Every
  `…ByPart` / `bodyParts` / `part:` surface is now keyed by `MuscleGroup`:
  `CoachPlanOptimizer`, `CoachFacts`, `CoachRuleSupport`, `CoachSession`,
  `RecoveryState`, `WeeklyPlan.SessionFocus`, `Insight`, `Recommendation`,
  `InsightRule`, `RecommendationRule`, `PlanAwareInsightEngine`,
  `SessionEligibilityPolicy`, `WeeklyStats`, `TrainingFacts`, `VolumeLandmarks`,
  `WorkoutHistory`, `WorkoutRepository`.
- `MuscleCatalog.canonicalName` extracted to the new
  `CadenceCore/Sources/CadenceCore/ExerciseNameCanonicalizer.swift` (name
  canonicalization, not muscle vocabulary — it had other callers).
- `ExerciseFacetIndex` protocol requirement is now `trainedMuscleGroups`, backed
  by `Exercise.trainedMuscleGroups` / `ExerciseTemplate.trainedMuscleGroups` in
  `ExerciseDiscovery.swift`: DB++ volume-credit keys first, canonicalized
  primary+secondary muscles as the fallback so a non-eligible movement stays
  browsable.
- Picker chips (`ExercisePickerView` + `+Controls`), `CustomExerciseEditView`,
  the picker's creation sheet, `PlanningView`, `ProgressView`,
  `RoutineDetailView`, `CustomExerciseListView`, `HomeView`,
  `CoachDecisionCardView+Presentation` and
  `CoachOverrideConfirmationModifier` all migrated.
- `BodyPartQuickStartView.swift` → `MuscleGroupQuickStartView.swift` (git-tracked
  rename; still dead code that compiles).
- Watch: `WatchAddExerciseView`, `WatchExerciseSelection`,
  `WatchCustomExerciseDefinition`, `WatchStrengthFlowModel` on `MuscleGroup`.
  The wrist category list is the 13 tracked groups in `MuscleGroup.canonicalOrder`
  with a **More muscles** row revealing the other seven.
- New test file `CoachPlanOptimizerMuscleGroupTests.swift` (4 tests) — the file
  the phase-6 plan asks for: tracked-only targeting, no session-length growth vs
  the 8-part baseline, upper/lower split assignment, group-window recovery gating.
  Each was checked non-vacuous by printing its intermediate state before the
  prints were removed.
- `BodyPartTests.swift` deleted (`git rm`).
- `scripts/check-test-pyramid.sh`: the grandfather ratchet table is now **empty**.
  All six previously-grandfathered views measure 161 / 200 / 313 / 281 / 201 / 364
  LOC, under the plain 400 budget, so none of them may grow again.

### Test-migration conventions worth keeping

- **`trackedSets(baseline:_:)`** (in `CoachPlanOptimizerTests`) — DB++ tracks 13
  groups, so a test meaning "everything is satisfied except X" must name all 13.
  Naming only 8 leaves the other five reading as zero-volume deficits that
  out-rank the group the test is about. This was the cause of most of the 36
  post-rename failures.
- **One set now credits several groups**, so summing `weeklySetsByGroup.values`
  across groups is no longer the set count. Assert the *direct* credit for one
  group instead (see `PartnersAndUnitsTests`).
- `CoachSchedulePreferences` decodes legacy `excludedCoverageParts` and folds it
  into `trackedMuscleGroups`, but **never encodes it again** — pinned by
  `testLegacyExcludedCoveragePartsIsNotWrittenBack`.

### Verification so far

| gate | result |
|---|---|
| `make ci` | **green — 1,652 tests, 0 failures**, test-pyramid + no-network/citation guardrails OK |
| `xcodebuild build -project Cadence/Cadence.xcodeproj -scheme Cadence` | BUILD SUCCEEDED (both schemes) |
| `make smoke` (iPhone) | **passed** — 1 test, 257.9 s |
| `make watch-smoke` | **passed** — 1 UI test, 0 failures (post-fix rerun) |

Phase-6 acceptance grep is clean: the only surviving `BodyPart` / `MuscleCatalog`
strings in Swift sources are explanatory comments plus one deliberate
legacy-compat assertion string in `CoachSchedulePreferencesCodableTests.swift`.

**Invocation note:** `xcodebuild` must be given the project explicitly —
`xcodebuild build -project Cadence/Cadence.xcodeproj -scheme Cadence …`. A bare
`-scheme Cadence` from the repo root picks up `WidgetTemplate.xcodeproj` and
fails with `Unable to read project`.

### The watch smoke failure and the two fixes made for it

The watch smoke test broke **because of a real ordering change**, not flake, and
it broke twice in a row for two different reasons:

1. `Cadence_Watch_App_Watch_AppUITests.swift:41` — the retired category order was
   `[.chest, .back, .legs, …]`, so `watchAddExercise.category.chest` was the first
   row and `tapButton(…)` found it with no scrolling. `MuscleGroup.canonicalOrder`
   is descending-mass (`glutes, quadriceps, lats, chest, …`), so Chest is now the
   **4th** row and sits below the fold on a 45 mm screen. `tapButton`'s
   `swipeUp()` fallback does not reliably scroll a watchOS `List`.
   **Fix applied:** both chest taps (lines ~41 and ~78) now use
   `tapButtonAfterSmallScroll("watchAddExercise.category.chest", attempts: 8)`,
   the coordinate-drag helper that already exists for exactly this, with a comment
   saying why. Mass order was kept: `canonicalOrder` is what every other surface
   uses, and the point of it is that two surfaces can never disagree about order.
2. Next run got past that and failed at line ~45,
   `watchAddExercise.row.Alternating Floor Press`. Confirmed by a throwaway test
   that Alternating Floor Press **is** the alphabetically first of the 146 chest
   movements, so the list content is right — the problem is that tapping a
   category swaps the same `List`'s content in place and **inherits the scroll
   offset** the test just built up, opening the group list ~150 pt down.
   **Fix applied (product fix, not a test hack):** `WatchAddExerciseView.picker`
   now carries `.id(pickerBranchIdentity)`, where the identity is
   `search` / `group.<rawValue>` / `recent` / `categories`. A branch change
   re-identifies the List so every list starts at its top; it deliberately does
   **not** key on `query`, which would reset the search field on each keystroke.

Both fixes are in the working tree. The post-fix `make watch-smoke` rerun passed.

## Immediate next task

1. Commit phase 6 — `refactor: replace BodyPart with MuscleGroup everywhere` —
   staging everything **except `current_status.md`**. Allow **≥900 s** for the
   commit: the pre-commit hook runs both simulator smoke gates.
2. Then **phase 8**, then **phase 9** (below).

### The standing instruction from the user this session

> "read current_status.md and proceed until completion of all phases then commit
> push and check ci"

That **overrides step 6 of the execution protocol above**: pushing is now
explicitly authorized. After the last phase commits: `git push origin main`, then
`gh run list --branch main --limit 1`, and report the SHA and CI status.

## Phase 8 — DONE (evidence and docs)

Plan file: `plans/exercise-db-plusplus/2026-08-23/08-evidence-and-docs.md`.
Independent of phase 6. Adds `ExerciseEvidence`, registers the 60 DB++ references
as citations under an `exdb.` id prefix with a `CitationRegistry.citation(forId:)`
fall-through, renders muscle roles + evidence in `ExerciseDetailView`, emits a
generated block in `docs/CITATIONS.md`, adds `scripts/check-citations-sync.sh`,
and updates the README and attribution. `make ci` is green with **1,648 tests**;
the app target build and `make smoke` are green. Three provisional DB++ patterns
(`wrist_flexion`, `wrist_extension`, `dorsiflexion`) have no reference IDs in the
snapshot, so the UI surfaces their summaries without inventing citations. The
curated registry remains **59** entries; movement evidence is a separate tier.

## Phase 9 — DONE (similar-exercise swap picker)

**Added 2026-08-24 at the user's request.** Depends on phase 6 (it is keyed by
`MuscleGroup` and by DB++ roles); does not depend on phase 8. This is the last
phase.

### The request, verbatim

> for "exercise picker swap" on resistance workouts, now that we have better
> exercise metadata, when you do "swap" in the workout, could you change it from
> free-text search to similarity search, in other words when you open it it says
> "Swap with a similar exercise" and below that could you add a toggle tab bar for
> the exercise types (e.g. strongman, olympic, etc — default to the current
> exercise being swapped but let the user pick others) so you can by default see
> the list of the "most similar to current exercise" exercises, that is that have
> the closest (or identical) as judged first in the selected category (strongman,
> olympic, etc) and direct/indirect set muscle mapping, sorted in descending order
> of similarity (most similar first).

### What shipped

- `ExerciseSimilarity` is a shared, pure DB++ ranker using direct/indirect role
  Jaccard overlap, movement patterns, mechanics/force, equipment/modality, type
  bias, volume eligibility, source exclusion, and deterministic tie-breaks.
- `ExerciseSwapPresenter` prepares the same ranked state for app surfaces.
- Resistance-workout swap entry points pass the source exercise. Phone swap mode
  opens on “Swap with a similar exercise”, defaults to the source type, exposes
  available training-type tabs, labels borrowed results under “Other types”,
  shows direct/indirect mappings and scores, and keeps “Search all exercises”
  as an escape hatch.
- The obsolete name-heuristic `ExerciseSubstitution` implementation is deleted.
- Four focused similarity tests pass; `make ci` is green with **1,652 tests**,
  the app target build is clean, and `make smoke` passed.

### What the code does today

- `Cadence/Cadence/Features/Train/ExercisePickerView.swift` (281 LOC) has
  `PickAction.add / .swap / .use`. **`.swap` currently changes nothing but the
  navigation title and the detail button label** — the user still gets the
  Recents / Popular / Browse tabs and free-text search, with no idea what they
  are swapping *from*.
- Swap entry points, both of which know the source exercise and both of which
  currently throw that knowledge away:
  - `Cadence/Cadence/Features/Train/SessionView+Rendering.swift:142` — the
    `swapTarget` sheet (`.planned(name:)` → `.swap`, `.logged(exerciseID:)` →
    `.use`), applied by `swapPlannedExercise(oldName:newName:)` /
    `WorkoutRepository.changeExercise`.
  - `Cadence/Cadence/Features/Home/WorkoutPlanEditor.swift:226` —
    `ExercisePickerIntent.swap(UUID)` → `applyPickedExercise`.
- `CadenceCore/Sources/CadenceCore/ExerciseSubstitution.swift` already exists and
  is **the thing to replace**. Its doc comment claims the watch swap screen and
  the phone picker share it; its scoring is real but every lookup —
  `movementPattern(of:)`, `category(of:)`, `primaryMuscles(of:)`,
  `equipment(of:)` — is a `name.lowercased().contains(…)` heuristic explicitly
  marked *"mock until integrated with ExerciseLibrary"*. It thinks a deadlift is
  a barbell "pull" for "hamstrings, glutes, back". DB++ now knows better.

### Design

**Similarity is computed against the DB++ annotation, not names.** Score one
candidate template against the source, all components normalized to 0…1 and
weighted:

| signal | weight | how |
|---|---|---|
| direct-muscle overlap | 0.45 | Jaccard of `directMuscles` sets |
| indirect-muscle overlap | 0.20 | Jaccard of `indirectMuscles` sets |
| movement pattern | 0.20 | 1.0 for a shared `movementPatternIDs` entry, 0.5 for a shared coarse `MovementPattern`, else 0 |
| mechanics + force | 0.10 | 0.05 each for equal `mechanicsValue` / `forceValue` |
| equipment | 0.05 | 1.0 equal, 0.5 same `ExerciseModality`, else 0 |

Tie-breaks, in order: in-style before borrowed, `volumeEligible` before not,
recently-performed before never, then `MuscleGroup.canonicalIndex` of the first
direct muscle, then name. The source exercise itself is excluded. **Identical
direct+indirect mapping must score 1.0 on both muscle terms** — that is the
"closest (or identical) … muscle mapping" the request asks for.

**The type tab bar** is `ExerciseTrainingType` (`ExerciseTaxonomy.swift`:
`strength`, `powerlifting`, `olympicWeightlifting`, `strongman`, `plyometrics`,
`cardio`, `stretching`, `mobility`). Only types with ≥1 candidate for the source's
muscle profile are shown. **Default = the source exercise's own training type**
(first of `trainingTypes`, falling back to `.strength`).

**The type filter biases, it never empties the list (NFR-8).** Same two-pass shape
phase 7 established for `SuggestedWorkoutStyle`: pass 1 ranks within the selected
type; pass 2 ranks everything and appends only what pass 1 could not supply, under
a visible "Other types" section header. A user who picks *Strongman* for a curl
still gets usable options and can see that they were borrowed.

**Escape hatch:** the existing search field and Browse tab stay reachable —
the similarity list is the *default* content of swap mode, not a cage. A
"Search all exercises" row returns the current picker behaviour.

### Layout (swap mode only; add/use modes are untouched)

```
┌─────────────────────────────────────┐
│  Swap Exercise                 Done │
├─────────────────────────────────────┤
│  Swap with a similar exercise       │
│  Replacing: Barbell Bench Press     │
│                                     │
│ ┌Strength┐ Powerlifting  Strongman ▸│   ← ExerciseTrainingType tab bar
│ └────────┘                          │      (default = source's own type)
│                                     │
│  MOST SIMILAR                       │
│  Dumbbell Bench Press          98%  │
│    Chest · Triceps, Shoulders       │
│  Floor Press                   91%  │
│    Chest · Triceps                  │
│  Machine Bench Press           88%  │
│    Chest · Triceps, Shoulders       │
│  …                                  │
│                                     │
│  OTHER TYPES                        │   ← only when pass 1 under-fills
│  Log Press                     72%  │
│                                     │
│  🔍 Search all exercises            │
└─────────────────────────────────────┘
```

Each row shows direct muscles in full colour and indirect muscles secondary, so
the muscle mapping the ranking is based on is visible rather than implied.

### Where the code goes

- **New** `CadenceCore/Sources/CadenceCore/ExerciseSimilarity.swift` — pure,
  `swift test`-verifiable. Takes prepared value structs (name, direct, indirect,
  patterns, mechanics, force, equipment, modalities, trainingTypes,
  volumeEligible), never `Exercise`, so it tests headlessly.
- **Delete** `ExerciseSubstitution.swift` and re-point its callers. Its
  name-heuristic lookups are strictly worse than the annotation and having two
  rankers would let the wrist and the phone disagree. *(Check the watch swap
  screen actually uses it before deleting; the doc comment may be aspirational.)*
- **New** `CadenceCore/Sources/CadenceFeatures/ExerciseSwapPresenter.swift` —
  builds the prepared state: available type tabs, selected tab, ranked sections,
  per-row muscle subtitle strings. Under 400 LOC (pyramid budget).
- `ExercisePickerView` gains a swap-mode branch that renders the presenter's
  state; it must **shrink or hold** at 281 LOC — put the new rows in a separate
  view file if needed.
- Both swap call sites pass the source exercise into the picker
  (`ExercisePickerView(action: .swap, source: exercise)`).
- **Watch parity is required.** Replace the watch swap path's retired
  `ExerciseSubstitution` heuristic with the same `ExerciseSimilarity` engine and
  `ExerciseSwapPresenter` prepared ranking as the phone. Its watch-native UI
  opens on “Swap with a similar exercise”, defaults to the source exercise's
  training type, lets the user change among the available type tabs, visibly
  separates borrowed “Other types” results, and preserves search/all-exercises
  as an escape hatch. The two renderers may differ for screen size, but ranking,
  score, exclusion, tie-breaks, and DB++ muscle-role data must be shared so an
  iPhone and watch never disagree about which substitutes are most similar.

### Testing

`swift test` (`ExerciseSimilarityTests`, `ExerciseSwapPresenterTests`):

- Identical direct+indirect mapping ranks first and scores 1.0 on both muscle
  terms.
- A movement sharing only *indirect* muscles ranks below one sharing *direct*
  muscles.
- Real-catalog assertion: swapping **Barbell Bench Press** puts a chest press
  variant in the top 3 and does **not** surface a curl.
- The selected type biases but never empties: swapping a curl with *Strongman*
  selected still returns rows, and the borrowed ones are flagged as borrowed.
- Default tab equals the source's own training type; a source with no
  `trainingTypes` defaults to `.strength`.
- Type tabs are only offered when they have candidates.
- Sorted strictly descending by score, with the documented tie-break order.

UI: extend the **existing** iPhone smoke test (never add a test function) with a
swap in the live session — open swap, assert the "Swap with a similar exercise"
header and the default type tab, pick the top similar row, assert the session now
holds it.

Watch UI: extend the existing watch smoke test (never add a test function) with
a live-session swap that asserts the similarity-first header/default type and
successfully applies its top ranked replacement. Add headless presenter tests
for parity; the shared ranking tests remain platform-independent.

### Acceptance

- [ ] Swap mode opens on a ranked similarity list, not on Recents/free-text.
- [ ] Header reads "Swap with a similar exercise" and names what is being replaced.
- [ ] Type tab bar defaults to the source's own training type and is switchable.
- [ ] Ranking is driven by DB++ direct/indirect roles; `ExerciseSubstitution`'s
      name heuristics are gone.
- [ ] Borrowed (out-of-type) results are disclosed, not hidden, and the list is
      never empty.
- [ ] Search and Browse remain reachable from swap mode.
- [ ] iPhone and watch use the same DB++ similarity ranking and both expose the
      similarity-first swap experience with a type filter and search escape hatch.
- [ ] `make ci` + `make smoke` green.

## Carried forward, not part of any phase

**Deploy the CloudKit Production schema before the next TestFlight or production
build.** Phase 3 added ten fields to `Exercise`; without a Dashboard deploy those
records will not sync. See the phase-3 section above.

## Standing rules (these outlive any one batch)

- **Swift 6 strict concurrency, warning-free.** A green local `swift build` does
  not mean a green warning gate: incremental builds do not re-emit warnings for
  untouched files, and the app target's gate is a separate CI step. Clean-build
  both and run `scripts/check-owned-warnings.sh` before pushing.
- **The iPhone UI suite is exactly one test** and the watch UI suite is exactly
  one test (`EXPECTED_IPHONE_SMOKE_TESTS=1`). New coverage extends the existing
  end-to-end flow or goes to `swift test`.
- **Assertions behind `if …exists` are worth little.** Make the flow do real work.
- **`uiTestMode` hides whole subsystems.** For a bug in HealthKit/BLE/WatchKit
  territory, reach for a unit test that crosses the framework boundary, not a UI
  test.
- **This repo has its own simulator**, `Cadence-iPhone-16`. If `xcodebuild` says
  it cannot find that device while `simctl` lists it, retry — it is a
  CoreSimulatorService hiccup. If launches balloon (~45s, `no debugger version`),
  `killall -9 com.apple.CoreSimulator.CoreSimulatorService` and re-run; report
  honestly which failures are environmental.
- **Resolve "what should this set be" in `PerformerSetPlanner` only.**
- **Logic lives in `CadenceCore` / `CadenceFeatures`; SwiftUI renders prepared
  state.** `CadenceFeatures` may not import SwiftUI/UIKit/HealthKit/StoreKit.
- **Every user-visible science claim resolves through `CitationRegistry` and
  renders with `CitationLink`.** Never display a raw citation id.
- **Persistence changes are additive only** (optional/defaulted) — CloudKit.
- The pre-commit hook takes >10 minutes (it runs both smoke gates). Allow at
  least 900s for `git commit`; `git push` needs little time.

## Known, deliberately not fixed

When a plan is silent at a given set index, the card's pending row shows the
*prior* session's load while the set editor shows what that performer lifted
*today*. Fix it by having `SessionRenderModel` seed
`History.firstWorkingWeightKg` from the last set logged this session, the way
`SessionView.resolvedSet` already does.

## Outstanding field verification (predates this plan)

1. **The 2026-08-19 batch on device** — custom workout with a partner (planned
   reps *and* weights surviving Start, alternating sets), switching performer
   mid-entry, a movement the partner has never done, and picker responsiveness
   during a live workout.
2. **The watch fix on hardware** (`7a5d6c7`) — Live HR → Start monitoring, the
   phone's pre-cardio HR request, and the stale "Resume Strength - Upper Body"
   row. Automated evidence cannot supply this.
