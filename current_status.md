# Current Status

Updated: 2026-09-17

## Active task — remove weekly planning; add individual scheduled workouts

The implementation target is now a single-workout workflow. Remove the
permanent Plan tab and retire weekly coach-plan creation from the user-facing
product. Preserve legacy weekly-plan SwiftData records and compatibility types
so existing private iCloud data is not destroyed.

### Product contract

- Home, Tests, and Progress remain top-level tabs; Plan is removed.
- Personalized Workout and Custom Workout remain the primary planning flows.
- Workout Plan View gets a `Schedule this Workout` button immediately below
  `Start Workout`, using the same button size and style family.
- Scheduling stores an exact snapshot of the reviewed workout, including
  exercises, notes, sets, reps, fractional historical weights, load modes,
  warm-up/cool-down, and partner prescriptions.
- Scheduling is app-internal date scheduling. Do not request EventKit access or
  create an Apple Calendar event in this task.
- After a successful save, the date sheet and Workout Plan close and Home is
  shown.
- Home gets `Planned Workouts` immediately below `Workouts Today`. Its compact
  section shows today’s scheduled workouts; `Show More…` shows today and future
  workouts, with overdue uncompleted items still recoverable in the full view.
- Starting a scheduled workout uses the normal live-workout path. Completed
  scheduled items leave Planned Workouts and appear in completed history.
- No DB++ schema change is required: schedule dates and execution lifecycle are
  app-owned private-user state.

### Persistence contract

Add an additive CloudKit-compatible `ScheduledWorkout` SwiftData model with:
`id`, normalized `scheduledDate`, semantic `scheduledDayKey`, timezone ID,
title, versioned payload data, payload version, scheduled/started/completed/
cancelled status, optional started-session ID, created/updated dates,
`deletedAt`, and `originDevice`. Use tombstones, not destructive deletion.
Add it to `CadenceStore.schema` and both CloudKit schema guardrail maps.
Keep `PersistedPlan` and normalized weekly-plan models in the schema, but stop
creating or displaying new weekly coach plans.

The scheduled payload is a versioned Codable app-side snapshot. It is not a
mutable reference to a generated plan. Existing Workout Plan edits must be
captured at the moment the user taps Save.

### Weekly-planning removal

Remove `Tab.plan`, `PlanningView`, weekly-plan generation/editing affordances,
`Generate with Coach`, `Describe a plan`, `New blank week`, weekly-plan routes,
and weekly-plan onboarding copy. Retain coach facts, insights, readiness,
training preferences, citations, and Personalized Workout inputs where still
needed. Old `cladiron://plan` and Handoff links must safely route Home rather
than expose a dead route.

### Schedule UI and lifecycle

Add a date-only schedule sheet with today/future validation, explicit Save and
Cancel, persistence error handling, and a visible confirmation. Thread an
`onSchedule` callback through the suggested and custom Workout Plan routes; the
root Home route performs the final navigation reset after persistence succeeds.
Do not create a `WorkoutSession` merely by scheduling. On start, copy the exact
payload into a session, link it with `scheduledWorkoutID`, and mark the schedule
started. Mark it completed only when the workout actually ends. Reschedule,
start-now, delete, crash recovery, and duplicate same-day schedules must all be
explicit and deterministic.

### Performance work required in this task

- Move Home coach value extraction (`TrainingFacts`, events, engine history,
  custom-volume extraction) off the main actor using a SwiftData model actor or
  background value-snapshot worker; only publish the final immutable snapshot on
  MainActor.
- Move Watch settings/custom-exercise payload construction off the main actor.
- Cache and hash Watch payloads; coalesce repeated foreground/settings sends and
  skip unchanged `updateApplicationContext` calls.
- Keep CloudKit event handlers tiny and debounce import bursts. Refresh Home only
  when a relevant workout/cardio/scheduled-workout signature changes; do not
  rebuild the coach for every imported entity or notification.
- Move bulk HealthKit ingestion/save work off the main SwiftData context.
- Add signposts around coach extraction, Home projections, HealthKit ingestion,
  Watch payload construction/transmission, and CloudKit import handling.

### Acceptance requirements

Core tests must cover payload round-trip, fractional weights, reps, partners,
timezone/DST date semantics, today/future/overdue filtering, tombstones,
duplicate same-day schedules, and start/complete/abandon/delete lifecycle.
Smoke tests must prove there is no Plan tab, no weekly coach-generation action,
both Personalized and Custom Workout Plan screens expose equal-sized Start and
Schedule buttons, scheduling returns Home, Planned Workouts renders today and
future entries, and starting a scheduled workout preserves its exact plan.
No simulator is part of this implementation pass. Commit with `--no-verify`
only after code and focused verification are complete, then push.

### Implementation completed in this pass

- Added `ScheduledWorkout` as an additive app-owned SwiftData/CloudKit model,
  including versioned exact-plan payloads, fractional loads, partner plans,
  tombstones, date-only timezone semantics, and linked session lifecycle.
- Added Schedule Workout UI below Start Workout, Home Planned Workouts today and
  future/overdue views, rescheduling, deletion, start/resume routing, and return
  to Home after save. The former Plan tab and unreachable weekly authoring views
  are removed; legacy weekly records remain in the schema.
- Removed automatic weekly coach-plan projection to Watch/widgets. Watch payload
  construction is detached, fingerprinted, and coalesced; Home coach extraction
  and HealthKit ingestion use background SwiftData contexts. CloudKit import,
  coach, Home projection, HealthKit, and Watch payload signposts are present.
- Added headless scheduled-workout payload/presenter/lifecycle/schema coverage
  and updated smoke/screenshot contracts to assert Plan is absent and scheduling
  is available. No simulator was run.

## Roadmap position — Phase 4 implementation complete; Phase 2 hardware close-out pending

Phase 3 implementation is complete for the active single-user roadmap slice.
The remaining Phase 2 work is field validation on real iPhone/Watch hardware
and same-user private iCloud convergence; those checks are documented in
`PHASE_2_MANUAL_TEST.md` and are intentionally not replaced by simulator runs.
Phase 3's human field checklist is in `PHASE_3_MANUAL_TEST.md`; the Phase 4
platform checklist is in `PHASE_4_MANUAL_TEST.md`.

### Completed

- **Phase 0 — foundations:** persistence, CloudKit schema and sync contracts,
  Watch payload boundary, and guardrails are complete.
- **Phase 1 — athlete implementation:** manual weekly planning, mixed-session
  boundaries, Watch projection, and the combined cardio/mobility runner are
  implemented.
- **Phase 2 code slice:** unified plan authoring/execution support, stale
  exercise-substitute protection, indexed/faceted exercise search, and normal
  descending planner rep ladders are implemented and covered by tests.
- **Phase 3:** unified-plan depth controls now expose mesocycles, periodization,
  progression intent, repeat-session, and repeat-week operations; the coach
  review surface exposes rationale, citations, critique, insights, progress,
  autoregulation, and explicit substitution acceptance; the optional $9.99
  contribution is the only StoreKit product and a successful purchase displays
  the Home Supporter badge without gating any feature.
- **Phase 4 implementation:** `BoundedPlanningRequestParser` now translates a bounded,
  deterministic natural-language vocabulary into the existing `PlanningRequest`
  contract. It supports goal, experience, days, duration, equipment,
  conditioning, constraints, progression, periodization, and mesocycle terms;
  it rejects retired trainer/client/Pro requests and never emits prescriptions.
  The former Plan tab and weekly coach authoring flow are now retired from the
  user-facing app; legacy planning models remain for migration compatibility.
  The optional readiness check-in is user-facing on Home. App Shortcuts,
  Handoff, and a WidgetKit extension use a
  privacy-preserving shared today snapshot. Focused tests cover the parser,
  persistence, readiness presentation, and platform snapshot contract. The parser
  now has 60+ phrase-level acceptance cases plus macOS `NaturalLanguage` tokenization
  parity coverage; the same framework is available to the iOS target.
- The app-side model extension was kept app-local; no upstream DB++ schema
  change is required for the current or planned product scope.
- **StoreKit cleanup:** the retired Pro subscription/trial/paywall path is
  removed from app launch, Settings, core models, and tests. `Cadence.storekit`
  contains only the optional `guru.parso.cladiron.tip.generous` consumable;
  successful purchase remains the sole path to the local Home Supporter badge.
- **Transparency and user control:** the project now requires visible status and
  plain-language control for automatic/background work. Settings exposes a
  Transparency & Control drill-down for HealthKit, Coach refresh, Watch
  projection, iCloud mirroring, Supporter prompts, and available retry/undo/
  recovery paths. Home visibly reports HealthKit ingestion and coach refresh
  while they are running; no authored plan is changed without explicit review
  and Apply.
- **iPad delivery smoke:** the iOS target now delivers to iPhone and iPad. The
  focused iPad smoke reuses the existing iPhone smoke method and checks only
  launch, Plan, bounded planning, Settings, and Transparency & Control; it does
  not duplicate the iPhone workout flow.

### Remaining Phase 2 close-out

These are the two final real-device validations and should be run together:

1. Authored/automated-coach plan → iPhone persistence → Watch execution →
   phone reconciliation.
2. Same-user private iCloud convergence across supported devices.

Phase 2 is therefore implementation-green but not formally closed until those
hardware and private-sync checks pass. No known commit or CI blocker remains.

### Remaining product work after this Phase 3 slice

- **Phase 4:** field-test the bounded request, readiness, widget, Shortcut,
  Handoff, larger-surface, accessibility, offline, and performance behavior;
  then complete the final acceptance matrix and Appendix AA compatibility proof.
- Across the remaining roadmap: add depth to cardio, mobility, instructions,
  larger-surface planning/templates/export, and the final v2.6 acceptance
  matrix plus Appendix AA compatibility proof.

Trainer mode, client sharing, Pro, trials, paywalls, and two-Apple-ID sharing
remain retired non-goals.

## Current work slice — Watch AppIcon recurrence guard — COMPLETE 2026-09-09

The Watch AppIcon files are present and valid, but a global `-sdk iphoneos`
override can force the embedded Watch target through the iPhone asset compiler.
This produces the misleading “AppIcon did not have any applicable content”
failure even when the Watch asset is correct. The checked-in Watch AppIcon
contract guard now validates the metadata, referenced PNG, dimensions, alpha
channel, and effective Watch target SDK. Repository-owned Xcode builds now run
through a wrapper that rejects explicit SDK overrides, and the destination-only
contract is checked in local guardrails and CI. Verification passed without
launching a simulator. The planner view-size violations were later cleared by
splitting the manual authoring and Planning surfaces into focused SwiftUI
files; the aggregate guardrails now pass.

## Current product scope correction — self-planned, automated coach only — COMPLETE 2026-09-09

The active roadmap is now explicitly single-user. There is no personal trainer,
client, Trainer mode, roster, human-coach delivery, invite/accept flow, CKShare
sharing, external-client packet, Pro tier, trial, paywall, or gated feature.
Planning is manual, template-based, or assisted by the automated scientific
coach; the user remains the author and accepts or edits suggestions.

The only planned purchase is an optional **$9.99 “Contribute to development”**
consumable. A successful purchase adds a **Supporter** badge to Home and
unlocks nothing. Core planning, coach assistance, execution, history, export,
partner sessions, and readiness remain available without purchase.

The authoritative plan and revision notes now mark the former trainer/client
and Pro roadmap as historical and retired. The active sequence is manual
self-planning, automated coach depth, optional Supporter handling, then
platform/readiness polish. Private iCloud remains limited to the user's own
devices. Existing compatibility code is not an invitation to expand the
retired model; remove or migrate it only as a separate cleanup task.

## Current investigation — cardio intensity credit consistency — INTERVAL-AWARE FIX COMPLETE 2026-09-15

Before this fix, the cardio paths disagreed. `TrainingEvent.from(cardio:userAge:)`
used both average and peak heart rate: at age 50, the app's age-based max HR is
about 173, so an average of 136 is 78.6% while a recorded peak of 170 is 98.3%;
the old peak threshold classified that session as vigorous and gave double
moderate-equivalent credit. The `YourWeekPresenter` intensity path used average
HR only, so it could show a lower/base intensity for the same workout. The HR
classification split was the defect addressed by the completed profile fix.

The better fix is not to promote the entire workout from its maximum sample. A
136 average with repeated 161 peaks at age 50 is consistent with an
interval-like effort: 136 is about 79% of the app's estimated HRmax of 173,
while 161 is about 93%. The current all-session buckets make that look like one
continuous moderate workout or, in the other path, incorrectly give the whole
session 2× credit. Official guidance also treats moderate and vigorous minutes
as additive and uses a 2:1 vigorous-to-moderate equivalence, so the app should
preserve the distribution of effort rather than discard it.

Implemented: `CardioZoneAggregator.IntensityProfile` now integrates the HR
curve over time with zone weights (easy 0.5×, moderate 1×, vigorous 2×). The
same profile feeds weekly zones, `TrainingEvent`, `CoachFacts`, and the Your
Week intensity surface. An `other` workout with at least two sustained Z4/Z5
bouts separated by recovery is marked interval-like without changing its
recorded modality. A single short peak does not trigger interval detection.
When samples are unavailable, the age/average/peak fallback remains in place
with lower confidence.

Regression coverage now includes age 50 / average 136 / repeated peak 161,
weighted high-zone credit, interval-like detection, isolated-peak rejection,
sampled `TrainingEvent` values, and conservative missing-HR fallback. The full
headless package suite passes with 1,772 tests; no simulator is required for
this logic.

## Historical investigation — complete exercise variants and indexed search — core fix shipped 2026-09-10

The upstream coverage is present. Free Exercise DB++ v1.16.0 adds the
vendor-neutral `Machine_Hip_Thrust` record and carries **Glute Drive** as a
search alias, based on Hammer Strength and Matrix catalog review. The app pins
DB++ 1.16.0, but its bridge currently drops aliases before building
`ExerciseTemplate`, and the existing search index only sees canonical names and
facets. This is why `glute drive` fails even though the upstream data caught it.

The catalog/search model should separate **display variants** from **exercise
identity**:

- Preserve DB++ aliases through `ExerciseRecord` → `ExerciseTemplate`, keeping
  one stable canonical exercise identity for sets, history, volume, and coach
  logic.
- Materialize every canonical name and alias as a visible, grouped variant in
  the exercise view. Selecting “Glute Drive” or “Machine Hip Thrust” must resolve
  to the same canonical exercise rather than creating duplicate database rows.
- Build each search document from the canonical name, every full alias phrase,
  equipment, muscles, force, mechanics, and curated synonyms. Store/recompute
  the derived alias tokens in `Exercise.searchKeywords` so existing stores gain
  the same coverage.
- Replace the current per-query full-catalog scan with one reusable inverted
  index: normalized word/prefix → matching canonical IDs/variant labels. Intersect
  postings for multi-word AND queries, rank exact alias/phrase matches first, then
  prefixes, names, and facets. Build once per catalog snapshot and reuse on every
  iPhone/Watch keystroke; invalidate only when the catalog or custom-exercise set
  changes.

Add an idempotent catalog/search migration (bump the seed/index version and
recompute derived keywords for all built-ins, not only rows whose keywords are
empty). Add headless regression/performance tests proving that `glute drive`,
`machine glute drive`, canonical names, aliases, prefixes, and facet terms all
return the correct grouped variant immediately, while alias and canonical
selection share one exercise identity and one volume/history record.

## Session restart checkpoint — CloudKit schema protection

The entire SwiftData/CloudKit model graph was audited. Development and
Production now match the checked-in contract across all 20 app record types and
every field/type. The final automated guard discovered two fields that had been
missing from both environments:

- `CD_HRMDevice.CD_lastBattery` (`INT64`)
- `CD_SetEntry.CD_note` (`STRING`)

Both fields were added to Development and have now been deployed to Production.
The live verification command is:

```sh
bash scripts/check-cloudkit-schema.sh
```

It reports: `cloudkit-schema: Development and Production match the contract`.

The prevention work is committed in `94fe15d` (`test: add CloudKit schema
contract guard`):

- `CloudKitSchemaCoverageTests` asserts all 20 persisted models and their exact
  SwiftData attribute sets.
- `scripts/cloudkit-schema-contract.tsv` records every CloudKit record, field,
  and CloudKit type.
- `scripts/check-cloudkit-schema.sh` compares both live CloudKit environments
  against that contract when `~/.cloudkit-management-token` exists; without a
  token it still validates the checked-in contract for CI.
- `make guardrails` runs the schema guard, so the installed pre-commit hook and
  CI execute it. The hook is installed in this clone via
  `scripts/install-git-hooks.sh`.

Final audit passed: `CloudKitSchemaCoverageTests` 3/3, the credential-free
contract check, the authenticated Development/Production comparison, and all
`make guardrails` checks. The audit also found and repaired one generated
exercise-citation documentation drift. `git diff --check` passes and the
pre-commit hook is configured at `scripts/git-hooks`. The follow-up CloudKit
diagnostics, entitlement split, readiness-model registration, citation sync,
and checkpoint edits are included in the next focused commit.

### Phase 0 closure — 2026-09-08

Phase 0 is closed. The unified model, runtime materializer, normalized
persistence, Watch payload boundary, send preflight, private-iCloud
configuration, CloudKit schema contract, sharing contract, and sync-performance
hardening are implemented and covered by the automated gates.

Two hardware validations are intentionally moved out of Phase 0: the plan-origin
iPhone/Watch execution test and the same-user private-iCloud multi-device test
are both Phase 2 close-outs. They will be run together after manual planning and
automated-coach workflows are available. Human trainer/client sharing and
two-Apple-ID invite/accept testing are removed from the roadmap.

The complete SwiftData/CloudKit contract is deployed and verified in both
Development and Production; the schema tests, authenticated live comparison,
all guardrails, and the installed pre-commit hook are green. The schema
protection work and the follow-up CloudKit diagnostics, entitlement, readiness,
citation, and persistence/configuration changes are committed.

The simulator gates also pass after making the Watch exercise-picker smoke
fixture catalog-agnostic: it now selects the first available second chest
exercise and derives its delete identifier from that row. The plan-origin
iPhone/Watch smoke path and same-user private-iCloud device gate are now tracked
as Phase 2 close-outs rather than blocking this closure.
Phase 1 manual plan authoring now supplies the first half of that combined
validation; Phase 2 automated-coach workflows will supply the second half.

## Sole active plan — revised Cladiron MVP v2.5

Authoritative plan:
`docs/plans/cladiron-mvp-revised/CLADIRON_PLATFORM_SPEC.md`

Revision summary:
`docs/plans/cladiron-mvp-revised/REVISION-NOTES.md`

Visual contract:
`docs/plans/cladiron-mvp-revised/mockups/index.html`

All implementation work must advance this roadmap. Earlier field-test, exercise
database, and DB++ engine-adoption plans are historical inputs, not active plans.
Do not start a new standalone plan when the work belongs to a v2.6 phase or work
stream; update this file and the authoritative spec instead.

## Product and licensing boundary

Cladiron is public and free/open-source under GPLv3-or-later with the Cladiron
App Store Exception. The application source, UI, app-specific coaching
composition, persistence, and Apple-platform integrations are covered by that
license. The Cladiron name, icon, logo, screenshots, and other brand assets
remain protected under `TRADEMARKS.md`; `free-exercise-db-plusplus` and its
materials remain under their own license. Keep these boundaries consistent in
the repository, About, support screens, App Store metadata, and release
documentation. The optional contribution is not a paywall and must not gate
features.

## Shipped baseline — preserve, do not rebuild

The revised MVP starts from a mature iPhone/Watch app, not a greenfield project:

- SwiftData persistence mirrored through the user's private iCloud;
- iPhone and Watch strength, partner, cardio, and interval execution;
- HealthKit, BLE heart rate, WatchConnectivity, workout history, and export/import;
- cited observations, suggestions, progress, assessments, and StoreKit scaffolding;
- `free-exercise-db-plusplus` 1.16.0 pinned behind the sole
  `TrainingEngineBridge` import boundary;
- 873 built-in exercises, 20 normalized muscles, evidence-audited roles and
  volume credits, movement classifications, and package-backed evidence;
- deterministic DB++ self-planning, history-derived state, adaptation,
  progression, serialization, and training-engine contract tests;
- app-owned readiness, pain, recovery, eligibility, presentation, and citation
  policy composed around DB++.

Standing invariants: Swift 6 strict concurrency, deterministic explicit-date
engine calls, no runtime network path, additive-only persistence, warning-free
builds, stable exercise IDs, package evidence resolved to app citations, and no
second exercise database/decoder or DB++ import site.

## Historical checkpoint — Phase 1 manual planning — implementation complete 2026-09-10

The required spec audit is complete in the closure map linked below. It covers
§§7–10, §§39–42, §47.0, Phase 0, `WS-EXECUTION-COMPAT`, and Appendix AA.
The matrix marks every Phase 0 requirement as:

- **verified shipped** — cite implementation and tests;
- **partial** — identify the exact missing model, invariant, test, or UI seam;
- **not started** — define the smallest dependency-ordered implementation slice;
- **superseded by v2.5** — only where the spec explicitly adopts the DB++ or
  existing SwiftData implementation instead.

Regression coverage is frozen around today's editable workout/coach-plan
materializer, collapsed strength cards, full-screen set editor, performer history
and alternation, 20-muscle credits, Watch strength/cardio lifecycle, and durable
phone reconciliation. The first smallest adapter, versioned Watch-payload,
in-memory sharing-contract, additive persisted unified-plan envelope, CloudKit
shared-zone adapter, and unified `Session` → runtime materializer slices are
landed; they do not
replace working private-iCloud sync, unplanned workout paths, Watch execution,
cardio, partner behavior, history/export, or the DB++ bridge.

Audit and closure map: `docs/plans/cladiron-mvp-revised/PHASE-0-EXECUTION-COMPATIBILITY-AUDIT.md`.
The first adapter, versioned Watch-payload, in-memory sharing-contract,
additive persisted unified-plan envelope, CloudKit shared-zone adapter, and
unified `Session` → runtime materializer slices are now landed in `CadenceCore`
and covered by focused contract tests. The CloudKit adapter now preserves the
saved share URL, plan revision/sentAt, and deterministic last-writer-wins
behavior across device writers.
The payload preserves legacy Watch fields, carries rich strength prescriptions
and planned cardio, and is consumed by Watch launch and phone reconciliation.
The reconciliation fixtures cover duplicate/out-of-order results and source-ID
preservation; the private self-sync contract covers change tokens, append-only
results, and same-user multi-device plan convergence. The unified value-model
conversion preserves strength/cardio/mobility/instruction item identity, and the
repository has a single `Session`-based start entry point. The editable iPhone
start path now converts its draft through that entry point while retaining
partner and DB++ provenance metadata; the legacy `EditablePlan.apply` path
remains compatible. Coach-generated weekly plans now also bridge into the
unified seven-day value graph, persist through `UnifiedPlanStore`, and enrich
Watch payloads from the same sessions. Phase 1 now starts with real manual plan
authoring. The deferred plan-origin iPhone/Watch smoke path and private
self-sync validation are Phase 2 close-outs and should be run together after
automated-coach plan workflows are available.
Do not
implement later-phase UI before the Phase 0 model and sharing boundaries
needed by it are explicit.

## Current work slice — workout-entry surface cleanup — SHIPPED 2026-09-05

User-requested UI cleanup that does not alter the Phase 0 value model or
sharing boundaries: remove the Home-level “Suggest a Workout” CTA while keeping
the action inside the Start Workout flow, and remove the non-functional
“Generate with Coach” action from the Custom Workout editor. Preserve the
working suggested-workout chooser reached from Start Workout. Implemented in
the Home observations component and Custom Workout editor; the smoke contract
now asserts both removals and the retained entry point. Verification: `make ci`
(build, 1,718 tests, four guardrails) passed; `make smoke` passed on its second
run after an unrelated first-run simulator flake at This Week expansion.
The pre-commit full gate also passed iPhone smoke, Watch build/unit smoke, and
Watch execution smoke. GitHub Actions run `33982770430` could not start its
test job because the repository account's payments/spending limit is blocked;
no remote code failure was reported.

The plan-origin iPhone/Watch smoke path and same-user private-iCloud convergence
are now paired Phase 2 close-outs after real manual and automated-coach plan
authoring exist. The normalized persistence mapping is in place; human
trainer/client sharing is not planned.

## Current work slice — Phase 0 persistence and send safety — SHIPPED 2026-09-05

The next Phase 0 slice is implemented: unified plans now have normalized
SwiftData header/week/day/session/item/set rows with stable IDs, coach-generated
Home plans write the normalized tree alongside the compatibility envelope. The
legacy client-relationship/share metadata remains only as compatibility state;
the v2.6 roadmap does not expand it.
`PlanSendPreflight` now blocks shared plans that contain invalid or
unsnapshotted `%1RM` loads. The Apple-ID account gate is wired into app startup
and Settings, which reports the real iCloud account state rather than always
claiming sync is on. Focused tests cover all item families, stable-ID updates,
relationship round trips, preflight rejection, and account-status mapping.

The plan-origin iPhone/Watch smoke path and same-user private-iCloud convergence
are paired Phase 2 close-outs after real manual and automated-coach plan
authoring exists. The live two-Apple-ID invite/accept test and macOS Trainer
dependency are removed from the roadmap.

The unified cardio-to-Watch producer now preserves steady-state distance goals
and heart-rate zones (and interval work-zone metadata) through the versioned
`PlanSessionSnapshot`/`WatchPlanPayload` boundary. Focused adapter tests cover
the generated payload, including these fields; this closes a data-loss seam
before the remaining device smoke gate.

## Current work slice — private iCloud sync performance — SHIPPED 2026-09-10

The iPhone store was audited against the reported repeated-restore behavior. The
production path uses one SwiftData `ModelContainer` backed by Apple's managed
private CloudKit mirror; there is no app-owned full-workout-history `CKQuery`,
startup restore loop, or repeated manual download path. CloudKit may still import
and export while the app is running because Apple's managed mirror controls that
scheduling; there is no public SwiftData API that can force it to run immediately
or restrict it to launch only.

The app now coalesces short CloudKit import events before releasing Home into its
history-derived coach rebuild, preventing one rebuild per import event. Generated
coach plans and their normalized trees now use content-aware no-op upserts, so a
fresh generation timestamp alone does not rewrite SwiftData or enqueue another
CloudKit export. Settings now shows only account availability and a link to a
separate iCloud Details & Diagnostics view; storage, legacy recovery, and status
checks are off the main Settings screen. The diagnostics view explicitly labels
normal sync as automatic/incremental and does not pretend its Refresh Status
button can force Apple's managed sync.

Focused persistence tests and the full CI gate pass, including all guardrails
and the live Development/Production CloudKit schema comparison. The changes are
included in the Phase 2 implementation commit. The plan-origin iPhone/Watch
smoke path and same-user private-iCloud convergence are paired Phase 2
close-outs after real manual and automated-coach plan authoring exists; there is
no macOS Trainer dependency.

## Phase queue

### Phase 1 manual planning — implementation complete 2026-09-10

The Plan tab now has a real self-authored weekly-plan path: create a blank
Monday-first week, add up to two sessions per day, edit session titles, choose
an exercise from the bundled searchable catalog, edit set type/reps/load/%1RM,
rest, and target RPE, and save through both the compatibility envelope and the
normalized SwiftData plan tree. Authored plans retain stable plan/session/item/
set IDs and can launch through the existing unified runtime materializer, so
this slice is ready for the Phase 2 plan-origin execution close-out once
hardware validation is approved. Authored plans now also project today's supported
strength/cardio sessions into the versioned Watch payload while retaining the
legacy Watch fields. A pure execution-boundary classifier now keeps
strength-only on the existing iPhone runner, allows pure cardio to remain a
Watch target, and routes cardio, mobility, and cardio-plus-mobility sessions to
the dedicated combined runner; instruction-only and strength-plus-cardio mixes
remain explicitly unsupported. No non-strength session is mislabeled as
executable strength work.

The pure `ManualPlanBuilder` contract is covered by five focused tests for
blank-week shape, stable-ID session replacement, the two-sessions-per-day limit,
and all four item families through envelope/normalized persistence. The compact
authoring surface now edits strength, steady-state/interval/open cardio,
timed-or-repetition mobility, and instruction items while retaining their stable
IDs and preserving the existing strength-only start boundary. Mixed sessions are
saved and handed to the unified value/runtime boundary; they remain explicitly
blocked from the current strength-only runner until the later execution slice.
The pure `ManualPlanWatchBridge` contract is covered by four focused tests for
strength identity/prescriptions, cardio legacy-plus-rich payloads, and the
unsupported instruction-only and mixed-session boundaries. The new
`PlanExecutionBoundary` contract covers empty, strength-only, cardio-only,
mobility-only, instruction-only, and mixed sessions. The new headless
`CombinedExecutionPlan`/`CombinedPlanRunner` contract preserves item order,
auto-advances timed cardio, requires explicit completion for open cardio and
mobility, freezes while paused, and rejects strength/instruction items. The
authored-plan start path reserves a distinct combined live-workout lease and
opens the iPhone runner; completed cardio segments persist through the existing
cardio history path. The generic iOS device build and focused/full package tests
pass. The Watch AppIcon guard
and destination-based Xcode guard also pass; the unsafe global SDK invocation is
rejected before Xcode starts. The full aggregate guardrails now pass after the
planner view-size cleanup, and no simulator was run. Partner workouts
and partner history remain an explicit preservation boundary: unified plan
`PartnerRef`s, runtime active-partner IDs, performer-specific prescriptions,
`performedBy` set attribution, Watch partner rotation, and partner summary
history are all still owned by their existing persistence/sync paths. The new
Watch bridge only adds today's executable strength/cardio projection and does
not rewrite or discard those partner fields.

| Phase | Status | Next outcome |
|---|---|---|
| 0 — foundations and sync proof | **COMPLETE 2026-09-08** | closed; Phase 2 owns the deferred device close-outs |
| 1 — athlete app | **IMPLEMENTATION COMPLETE 2026-09-10** | Phase 2 close-out validation of plan-origin execution and private self-device sync |
| 2 — automated scientific coach | **IMPLEMENTATION GREEN; CLOSE-OUT PENDING** | run the authored/coach plan device path and same-user private-iCloud convergence together |
| 3 — self-planning depth + optional contribution | **IMPLEMENTATION COMPLETE 2026-09-10** | field-review plan depth, coach review, contribution badge, then continue to Phase 4 |
| 4 — individual-user platform polish | **IMPLEMENTATION COMPLETE 2026-09-11; FIELD REVIEW PENDING** | execute `PHASE_4_MANUAL_TEST.md`, then final acceptance and Appendix AA proof |

## Status and next task — 2026-09-11

Current status: Phase 0 is complete, Phase 1 implementation is complete, and
the Phase 2 implementation slice plus Phase 3 self-planning/contribution slice
are green locally and ready for the authorized release commit. Strength-only sessions
still use the existing iPhone/Watch runner; pure cardio remains projectable to
the existing Watch cardio runner and can also run through the authored-plan
combined surface; mobility and cardio-plus-mobility sessions use the new iPhone
runner, while instruction-only and strength-containing mixes remain blocked.
Partner workouts and partner history remain preserved.

Immediate next task: complete the Phase 3 and Phase 4 human field checklists.
Phase 4's implementation slice now includes bounded request review/apply,
readiness capture, WidgetKit, App Shortcuts, Handoff, and the shared snapshot
contract. Phase 2 hardware and private-iCloud close-outs remain required field
validation and are not replaced by simulator runs.

Overall plan position: Phase 3 and Phase 4 implementation are complete and
field-testable, Phase 2 is implementation-green and field-test ready but not
formally closed until the two real-device validations pass, and the remaining
work is field acceptance plus the final compatibility proof.

## Execution rules

- Implement in phase and dependency order unless the spec explicitly identifies
  an independent work stream.
- Begin each work stream with a gap test against the shipped code; do not recreate
  an already-satisfied capability under a new type without a migration reason.
- Use the mockups as visual contracts, including dynamic type, accessibility,
  empty, loading, error, and offline states required by the
  spec even when a static mockup shows only the primary state.
- Keep the GPLv3/App Store Exception/open-project wording consistent in About/Help,
  support screens, App Store metadata, website copy, and release documentation.
  The optional contribution is not a paywall and must not gate features.
- Run focused tests during development and `make ci` before a phase/work-stream
  commit. Run iPhone/watch smoke gates whenever their user flows change. For
  this work slice, simulator and commit/push execution is intentionally deferred
  for review.
- Hardware verification remains mandatory for HealthKit, BLE, WatchConnectivity,
  workout runtime, and private-iCloud self-device sync on supported Apple
  surfaces. There is no human-coach sharing or Mail packet handoff gate.
- Do not push unless explicitly authorized. Preserve unrelated user changes.

## Definition of MVP-plan completion

The revised MVP is complete only when the active v2.6 acceptance criteria in §49
pass, the testing matrix in §50 is satisfied, the DB++ boundary remains intact,
the optional $9.99 contribution adds only the Home Supporter badge, and no core
feature is gated by purchase. Appendix AA must prove planning did not regress
DB++ muscle accounting, iPhone set entry, partners, cardio, or real-Watch
execution/reconciliation.
