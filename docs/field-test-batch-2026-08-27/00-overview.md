# Field-test remediation batch — 2026-08-27

Source: hardware field testing reported 2026-08-27. This batch contains nine
issues. Implement them in order, one phase and one local commit per issue. Do
not push any commit until the user explicitly approves a push.

## Phase map

| Phase | Outcome | Primary area | Required verification |
|---|---|---|---|
| 1 | Add Set rotates through the configured performer order | strength set entry | unit + iPhone smoke |
| 2 | Exercise search responds without multi-second per-keystroke stalls | exercise picker/search index | performance unit + iPhone smoke |
| 3 | Watch cardio reliably appears on iPhone after sync | WatchConnectivity/HealthKit ingest | unit + watch smoke + hardware |
| 4 | iPhone cardio reconnects to live watch HR | watch HR command/relay lifecycle | unit + iPhone/watch smoke + hardware |
| 5 | Connect HR can be cancelled back to Home | pre-workout navigation | unit + iPhone smoke |
| 6 | Watch cardio live layout shows time, optional zone-colored HR, GPS-only distance | watch cardio UI | unit + watch smoke + hardware |
| 7 | Watch cardio summary conditionally shows HR graph/max/average | watch summary | unit + watch smoke + hardware |
| 8 | Workout edit has large Save/Cancel actions; history detail has an explicit Back action | editor/history navigation | unit + iPhone smoke |
| 9 | Home Completed Workouts links to full History | Home/history routing | unit + iPhone smoke |

Each phase has its own implementation file in this directory. Those files are
the source of truth for scope and acceptance criteria.

## Execution protocol

1. Start only the next incomplete phase recorded in `current_status.md`.
2. Reproduce or pin the defect with a failing headless test where practical.
3. Implement only that phase. Shared infrastructure may be changed only when it
   is necessary for that issue and is covered by the phase's tests.
4. Run `make ci` for every phase. Also run `make smoke` for phases 1, 2, 5, 8,
   and 9; run `make watch-smoke` for phases 3, 4, 6, and 7. Run both smoke gates
   for phase 4 because it crosses both apps.
5. Adjust the existing smoke test functions; do not add additional XCUITest test
   functions. Preserve the repository's test-pyramid guard.
6. Update `current_status.md` with shipped behavior, exact test results,
   deviations, and the next phase.
7. Commit exactly one issue/phase. Use a phase-specific commit message and do
   not mix unrelated working-tree changes. Keep `current_status.md` uncommitted
   if that remains the repository convention at execution time.
8. Do not run `git push` until the user gives explicit approval.

## Cross-cutting constraints

- Preserve Swift 6 strict-concurrency and warning-free builds.
- Put deterministic behavior in `CadenceCore`/`CadenceFeatures`; SwiftUI views
  should render prepared state and forward actions.
- Persistence changes must remain additive/defaulted for CloudKit compatibility.
- Watch deliveries must be durable and idempotent. Do not depend solely on
  `sendMessage`, foreground reachability, or a single activation callback.
- Sensor-dependent UI must be conditional: no inferred GPS distance and no HR
  metrics when HR collection was disabled or produced no samples.
- Real-watch verification remains mandatory for phases 3, 4, 6, and 7 even
  after automated gates pass.

## Local commit sequence

Suggested subjects:

1. `fix: rotate strength set performers`
2. `perf: make exercise search incremental`
3. `fix: sync watch cardio to iphone`
4. `fix: reconnect iphone cardio to watch heart rate`
5. `fix: cancel heart rate connection flow`
6. `feat: refine watch cardio live metrics`
7. `feat: add heart rate chart to watch cardio summary`
8. `fix: clarify workout edit and history navigation`
9. `feat: link completed workouts to history`

