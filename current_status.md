# Current Status

Updated: 2026-09-07

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

### Next implementation item

Current Phase 0 status: the complete SwiftData/CloudKit contract is deployed and
verified in both Development and Production; the schema tests, authenticated
live comparison, all guardrails, and the installed pre-commit hook are green.
The schema protection work and the follow-up CloudKit diagnostics,
entitlement, readiness, citation, and persistence/configuration changes are
committed.

The simulator gates also pass after making the Watch exercise-picker smoke
fixture catalog-agnostic: it now selects the first available second chest
exercise and derives its delete identifier from that row. Continue Phase 0 with
the remaining same-user private-iCloud device verification and plan-origin
iPhone/Watch smoke path. One iPhone, one paired Watch, and the Mac are enough
for the same-user private-iCloud gate. The real two-Apple-ID invite/accept
gate is intentionally deferred until the later macOS Trainer app phase, when
the Mac can provide the second app-capable client; this project has no macOS
target yet.
The next code slice should prove that a generated plan retains its origin and
prescriptions across iPhone persistence, CloudKit sync, Watch launch, and
phone reconciliation without changing the working manual-workout path.

## Sole active plan — revised Cladiron MVP v2.5

Authoritative plan:
`docs/plans/cladiron-mvp-revised/CLADIRON_PLATFORM_SPEC.md`

Revision summary:
`docs/plans/cladiron-mvp-revised/REVISION-NOTES.md`

Visual contract:
`docs/plans/cladiron-mvp-revised/mockups/index.html`

All implementation work must advance this roadmap. Earlier field-test, exercise
database, and DB++ engine-adoption plans are historical inputs, not active plans.
Do not start a new standalone plan when the work belongs to a v2.5 phase or work
stream; update this file and the authoritative spec instead.

## Product and licensing boundary

Cladiron is public and free/open-source under GPLv3-or-later with the Cladiron
App Store Exception. The application source, UI, app-specific coaching
composition, persistence, and Apple-platform integrations are covered by that
license. The Cladiron name, icon, logo, screenshots, and other brand assets
remain protected under `TRADEMARKS.md`; `free-exercise-db-plusplus` and its
materials remain under their own license. Keep these boundaries consistent in
the repository, About, support screens, paywalls, App Store metadata, and
release documentation.

## Shipped baseline — preserve, do not rebuild

The revised MVP starts from a mature iPhone/Watch app, not a greenfield project:

- SwiftData persistence mirrored through the user's private iCloud;
- iPhone and Watch strength, partner, cardio, and interval execution;
- HealthKit, BLE heart rate, WatchConnectivity, workout history, and export/import;
- cited observations, suggestions, progress, assessments, and StoreKit scaffolding;
- `free-exercise-db-plusplus` 1.15.4 pinned behind the sole
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

## Immediate next task — Phase 0 unified model and Watch payload closure

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
preservation; the sharing contract covers invitation/acceptance, change tokens,
append-only results, and trainer-device plan convergence. The unified value-model
conversion preserves strength/cardio/mobility/instruction item identity, and the
repository has a single `Session`-based start entry point. The editable iPhone
start path now converts its draft through that entry point while retaining
partner and DB++ provenance metadata; the legacy `EditablePlan.apply` path
remains compatible. Coach-generated weekly plans now also bridge into the
unified seven-day value graph, persist through `UnifiedPlanStore`, and enrich
Watch payloads from the same sessions. Continue with the CloudKit Apple-ID/
device gate, normalized persistence mapping, and plan-origin device smoke path.
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

The remaining Phase 0 work is the same-user private-iCloud Apple-ID/device gate
and plan-origin iPhone/Watch smoke path; the normalized persistence mapping is
now in place below. The live two-Apple-ID share/invite gate is deferred until
the later macOS Trainer app phase.

## Current work slice — Phase 0 persistence and send safety — SHIPPED 2026-09-05

The next Phase 0 slice is implemented: unified plans now have normalized
SwiftData header/week/day/session/item/set rows with stable IDs, coach-generated
Home plans write the normalized tree alongside the compatibility envelope, and
client relationship metadata persists with lifecycle and share information.
`PlanSendPreflight` now blocks shared plans that contain invalid or
unsnapshotted `%1RM` loads. The Apple-ID account gate is wired into app startup
and Settings, which reports the real iCloud account state rather than always
claiming sync is on. Focused tests cover all item families, stable-ID updates,
relationship round trips, preflight rejection, and account-status mapping.

The remaining Phase 0 gaps are real same-user private-iCloud device
verification and the plan-origin iPhone/Watch smoke path. The live
two-Apple-ID invite/accept test is intentionally scheduled after the macOS
Trainer app is available.

The unified cardio-to-Watch producer now preserves steady-state distance goals
and heart-rate zones (and interval work-zone metadata) through the versioned
`PlanSessionSnapshot`/`WatchPlanPayload` boundary. Focused adapter tests cover
the generated payload, including these fields; this closes a data-loss seam
before the remaining device smoke gate.

## Phase queue

| Phase | Status | Next outcome |
|---|---|---|
| 0 — foundations and sync proof | **IN PROGRESS: value model + runtime + normalized persistence + send gate + Watch payload + sharing contract** | run the same-user CloudKit device gate and plan-origin iPhone/Watch smoke path; defer live two-ID sharing until the macOS Trainer phase |
| 1 — athlete app | pending | Plan-first iPhone/iPad experience, compact authoring, partner execution, migration |
| 2 — scientific coach | partial baseline shipped | extend DB++-backed engine into unified-plan Generate/Critique/Progress/Substitute/Autoregulate surfaces |
| 3 — iPad Trainer mode | pending | roster, planner, connected/external delivery, review, export, and Pro entitlement |
| 4 — iPhone Trainer + native Mac | pending | compact trainer parity, native Mac shell, Universal Purchase |
| 5 — depth and natural-language interface | pending | periodization, bounded language interface, readiness and platform polish |

## Execution rules

- Implement in phase and dependency order unless the spec explicitly identifies
  an independent work stream.
- Begin each work stream with a gap test against the shipped code; do not recreate
  an already-satisfied capability under a new type without a migration reason.
- Use the mockups as visual contracts, including dynamic type, accessibility,
  empty, loading, error, offline, and lapsed-entitlement states required by the
  spec even when a static mockup shows only the primary state.
- Keep the GPLv3/App Store Exception/open-project wording consistent in About/Help, paywalls,
  support screens, App Store metadata, website copy, and release documentation.
- Run focused tests during development and `make ci` before a phase/work-stream
  commit. Run iPhone/watch smoke gates whenever their user flows change.
- Hardware verification remains mandatory for HealthKit, BLE, WatchConnectivity,
  workout runtime, private-iCloud/CloudKit sharing behavior, and Mail/share-sheet
  handoff on iPhone, iPad, and Mac.
- Do not push unless explicitly authorized. Preserve unrelated user changes.

## Definition of MVP-plan completion

The revised MVP is complete only when all acceptance criteria in §49 pass across
the required idioms, the testing matrix in §50 is satisfied, the app and metadata
state the GPLv3/App Store Exception license, the DB++ boundary remains intact,
the free/Pro behavior matches §44 under Universal Purchase, and external-client
delivery passes criteria 35–39 plus Appendix Z's golden renderer, adapter,
privacy, cancellation, and idempotent manual-result tests. Criteria 40–45 and
Appendix AA must also prove planning did not regress DB++ muscle accounting,
iPhone set entry, partners, cardio, or real-Watch execution/reconciliation.
