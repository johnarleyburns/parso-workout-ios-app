# iPhone Home redesign verification

Generated 2026-08-15 after rereading the source and remaining-fixes handoffs.

## Automated results

- `swift test --package-path CadenceCore`: passed, 1,311 tests, 0 failures.
- Combined iPhone/Watch scheme build using the documented destination and no global SDK override: passed. Log: `/tmp/cadence-final-build.log`.
- `git diff --check`: passed.
- Remaining-fixes acceptance searches for old Home dashboard calculations and standard-tier Coach gates: passed.

## Exit matrix

| Gate | Status | Evidence |
|---|---|---|
| FT-01 Watch launch | blocked | Injectable policy, exact-file quarantine, serialized retry, logging, and failure-injection unit tests pass; paired Watch clean/upgrade/relaunch evidence unavailable. |
| FT-02 one workout | blocked | Atomic lease/start-intent unit coverage and exact-lease cleanup pass; every production deep-link/cardio route and physical race evidence not completed. |
| FT-03 Watch HR | blocked | Request-ID relay, typed acknowledgement/rejection payloads, stale-reply filtering, and request-scoped stop cleanup are implemented; paired Watch readiness and end-to-end evidence unavailable. |
| FT-04 performer | blocked | Picker and draft-preservation controls compile; Add Partner return/select UI and paired multi-person roll-up evidence unavailable. |
| FT-05 equal grid | blocked | Four/two-column implementation is present; frame assertions across required devices/orientations/Dynamic Type unavailable. |
| FT-06 interval timing | passed | Duration table, epsilon, short-work, runner-extension, and cue tests pass in the package suite. |
| FT-07 set latency | blocked | Stable editor identity, draft isolation, and duplicate root-gesture removal compile; physical release-build p95/max and signpost artifact unavailable. |

Physical-device and paired-Watch rows are explicitly blocked because that infrastructure is not available in this workspace; simulator/build success is not substituted for them.
