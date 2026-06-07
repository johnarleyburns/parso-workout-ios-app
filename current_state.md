# Current State — field-testing redesign

Live progress tracker for the 2026-06-06 field-testing plan
(`plans/field-testing/2026-06-06/`). Updated at the start of each phase.

_Last updated: start of Phase 3 (2026-06-07)._

## Phase status

| Phase | Scope | Branch | PR | Status |
|-------|-------|--------|----|--------|
| Planning | 8 design docs + decisions | — | — | ✅ done |
| 1 | §01 home/nav + §02 engine core | `feat/ft-shell` | #7 | ✅ done — 67 core + 21/21 UI green |
| 2 | §03 faceted exercise DB + search | `feat/ft-exercise-db` | #8 | ✅ core done — 68 core green, build green (UI: 17/21, 4 env-flaky) |
| 3 | §04 weight-training screen | `feat/ft-strength` (stacked on 1+2) | — | 🚧 in progress |
| 4 | §05 cardio outdoor GPS | `feat/ft-cardio-gps` | — | ⬜ todo |
| 5 | §06 interval engine (HIIT/boxing) | `feat/ft-intervals` | — | ⬜ todo |
| 6 | polish + settings | `feat/ft-polish` | — | ⬜ todo |

## What's landed (cumulative on the Phase 3 base)
- **Engine core**: `WorkoutClock`, `IdleWatchdog`, `WorkoutType`, `WorkoutSession.endedAt`, `ActiveWorkoutModel`.
- **Shell**: tab bar removed; `HomeView` launchpad + `WorkoutTypePicker`; old tabs re-homed; End Workout on session.
- **Exercise DB**: faceted `Exercise` (equipment/laterality/mechanics/force/muscles/keywords), `MuscleCatalog` synonyms, `ExerciseSearch` ranking, ~155-exercise seed, idempotent re-seed, ranked picker search.
- Core tests: **77 green** on the integrated base.

## Phase 3 plan (§04 — this phase)
Per `plans/field-testing/2026-06-06/04-weight-training-screen.md` + decisions #4/#13/#14/#15/#16:
1. **Core**: `UnitEntry` dual lb/kg helper (+ tests); add `ownerOnly` filtering to all PR/volume/last-time repo methods so partner sets are excluded.
2. **Model**: new `Person` (`isMe`), `SetEntry.performedBy` (optional ⇒ owner); export carries partner tag.
3. **Set editor**: dual lb/kg entry control (auto-fill, exact convert, optional plate-round off) + "For: Me/Partner" attribution.
4. **Session screen**: partner bar; attribution on rows; reuse-workout from history/Home; full idle-watchdog UI integration (10-min "Still training?" prompt).
5. **Templates**: removed from UI (schema retained); "Reuse workout" replaces them.
6. **Create-exercise** UI carries §03 facets.

## Known environment issue
- The CI simulator degrades over a session (~45s launches, `no debugger version`); fix by restarting CoreSimulator service. `swift test` (Mac toolchain) is the reliable gate; the `xcodebuild` UI suite can show env-flaky timeouts on correctly-rendered elements (FR1 set-logging, FR4 toggle were flaky in Phase 2).

## What's left after Phase 3
Phases 4 (cardio GPS), 5 (interval engine + full-screen color indicator), 6 (settings/polish). See the rollout table in `07-data-model-migration-and-rollout.md`.
