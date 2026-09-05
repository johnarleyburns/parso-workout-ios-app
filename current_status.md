# Current Status

Updated: 2026-09-04

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

Cladiron is proprietary, closed-source software. Remove GPL, App Store-exception,
and “Cladiron is open source” language from all current product, repository,
support, App Store, and in-app surfaces.

Required public wording:

> Cladiron is a proprietary, privacy-first application built on the open free-exercise-db-plusplus project. The exercise database, annotations, and related tooling remain freely available for use by other applications.

The open-project license applies to `free-exercise-db-plusplus` and its materials,
not to Cladiron's UI, app-specific coaching composition, persistence, HealthKit/
Watch integrations, documentation, or brand. Preserve all third-party notices.

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
phone reconciliation. The first smallest adapter and versioned Watch-payload
slices are landed; they do not
replace working private-iCloud sync, unplanned workout paths, Watch execution,
cardio, partner behavior, history/export, or the DB++ bridge.

Audit and closure map: `docs/plans/cladiron-mvp-revised/PHASE-0-EXECUTION-COMPATIBILITY-AUDIT.md`.
The first adapter and versioned Watch-payload slices are now landed in
`CadenceCore` and covered by focused contract tests. The payload preserves
legacy Watch fields, carries rich strength prescriptions and planned cardio,
and is consumed by Watch launch and phone reconciliation. Continue with the
dependency-ordered append-only/reconciliation fixtures in that audit. Do not
implement later-phase UI before the Phase 0 model and sharing boundaries
needed by it are explicit.

## Phase queue

| Phase | Status | Next outcome |
|---|---|---|
| 0 — foundations and sync proof | **IN PROGRESS: audit + session adapter + Watch payload** | complete the persisted unified Plan model, add append-only/reconciliation fixtures, then add the trainer/client sharing proof |
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
- Keep the proprietary/open-project wording consistent in About/Help, paywalls,
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
contain no claim that Cladiron is open source, the DB++ boundary remains intact,
the free/Pro behavior matches §44 under Universal Purchase, and external-client
delivery passes criteria 35–39 plus Appendix Z's golden renderer, adapter,
privacy, cancellation, and idempotent manual-result tests. Criteria 40–45 and
Appendix AA must also prove planning did not regress DB++ muscle accounting,
iPhone set entry, partners, cardio, or real-Watch execution/reconciliation.
