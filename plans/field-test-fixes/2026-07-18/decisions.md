# Decisions — field-test fixes 2026-07-18

Settled owner decisions. Do not re-litigate.

1. **In-progress workout vs coach recommendations** (asked 2026-07-18): when an unfinished
   (resumable) strength workout exists, the coach should **"Never block, just warn"** —
   recommendations always render; an in-progress session only adds an advice note
   ("finish your open workout first"). Chosen over "block same-kind only" and "keep blocking
   everything". Drives Phase A's removal of the `SessionEligibilityPolicy` active-workout defer.

2. **Per-phase shipping** (owner instruction, 2026-07-18): every phase must end with
   commit → merge to `main` → push → **CI green** before the next phase begins. No batching.

3. **Phase F step-summary threading**: overlay `stepSummary` at the call site rather than
   threading `activityTrend` into `CoachSnapshotBuilder` — putting raw step counts in the
   coach cache signature would re-run the expensive pipeline on every HealthKit refresh,
   defeating the cache. (Engineering decision recorded here so it isn't "fixed" later.)
