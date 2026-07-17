# W-final — Consolidated deltas, migration safety, rollout & testing

## Consolidated schema / contract deltas (all additive — no destructive migration)

| Layer | Delta | Phase | Migration risk |
|---|---|---|---|
| SwiftData | **none** — reuses `isWarmup`, `cooldownSeconds`, `endedAt`, kg-internal weights | — | none; JSON export/import untouched |
| WC applicationContext | `settings.unit` (+ optional `settings.colorBlind`, `settings.restSeconds`) | W2 | old watch ignores unknown keys |
| WC userInfo actions | `set_unit` (watch→phone), `discard_session` (watch→phone) | W2, W3 | phone's `default:` branch already ignores unknown actions (`AppModel.swift:192`) |
| HealthKit | share set grows: workoutType (existing) + activeEnergy + 3 distance types; workouts now **finished** (saved) | W1, W4 | user re-prompted once for new share types — expected |
| HKWorkout metadata | `guru.parso.cladiron.manualLaps` | W4 | additive |
| UserDefaults (watch) | `watch.settings.unit`, `watch.cardio.location.<type>`, `watch.swim.lapLength` | W2, W4 | defaulted |

Older phone builds paired with a newer watch: every new payload lands in an
ignore path; nothing crashes. Newer phone with older watch: context keys simply
unused. Safe both directions.

## Phased rollout

| Phase | Branch | PR contents | Depends on | Primary verification |
|---|---|---|---|---|
| **W1** | `watch/w1-hr-timer-save` | HR auth-gate fix; timeline-driven `runner.now`; state-driven `finishWorkout` teardown (+ `stopWorkout(save:)`); Live HR quick session (discarded) | — | device: BPM in <5 s; boxing counts down; workout hits rings + phone ingest; smoke asserts countdown advances |
| **W2** | `watch/w2-units` | `WeightIncrement`; watch `AppSettings` + locale default; Settings Units row; two-way WC unit sync | — (parallel with W1) | `swift test`; device round-trip lb↔kg |
| **W3** | `watch/w3-strength-flow` | `WatchStrengthFlowModel`; Strength naming; session home / keypad / rest / cool-down / summary split views; lazy session create; Cancel + `discard_session`; phone discard handler | W2 (unit display) | `swift test` transition table; device full + cancelled workouts |
| **W4** | `watch/w4-cardio` | `WorkoutConfigurationSpec`, `CardioMetricsModel`; launcher rework; setup/metrics/controls/summary views; pause/water-lock/laps | W1 (save teardown) | `swift test`; device matrix (outdoor walk, indoor cycle, pool swim, other) |
| **W5** *(backlog — not in scope for "watch-only")* | `watch/w5-polish` | Resume active session; Smart Stack complication; GPS `HKWorkoutRouteBuilder`; auto-pause; segments | W3, W4 | — |

Branching: W1 and W2 branch off `main`; W3 branches off W2 (stacked, per
CLAUDE.md); W4 branches off W1. Merge order: W1, W2, W3, W4.

## Test-pyramid compliance
- All new logic (`WatchAuthPolicy`, `WeightIncrement`, context reducer,
  `WatchStrengthFlowModel`, `WorkoutConfigurationSpec`, `CardioMetricsModel`)
  lives in **CadenceFeatures** — Foundation/SwiftData/Observation only, no
  SwiftUI — and is covered by headless `swift test`. This is where coverage grows.
- Watch UI smoke stays within its cap; the only change is asserting the interval
  countdown advances (bug-2 regression) inside the existing test.
- Every new/split watch view file stays under the 400-LOC budget
  (`WatchStrengthView` is split in W3 partly for this reason).
- `scripts/check-test-pyramid.sh` + `check-no-network.sh` must stay green each PR.

## Estimated new headless tests
W1 ~6 · W2 ~10 · W3 ~18 · W4 ~20 → **~54 new `swift test` cases.**

## Definition of done for "watch-only"
Phone in a drawer for a full week of training:
1. Strength day: warm-up sets → 3 lifts in lbs → cool-down → Save → appears on
   phone (merged, PRs correct) when next opened.
2. Boxing day: rounds tick, bells buzz, HR live, rings credit.
3. Outdoor run + indoor cycle: distance/pace/speed live, saved, ingested.
4. Pool swim: lengths count, water lock on, summary saved.
5. A cancelled workout leaves zero residue anywhere.
6. Units read **lb** everywhere without ever touching the phone.
