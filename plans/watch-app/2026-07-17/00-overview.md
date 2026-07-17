# Watch App v3 — "Watch-Only Fitness" — Plan Overview

_Date: 2026-07-17. Status: **PLAN ONLY — not yet approved for implementation.**_
_Predecessor: `plans/watch-app/2026-07-16/` (v2, shipped Phases 0–3 + handoff; CI green)._

## Context — field feedback from the real device

v2 shipped and installs, but the first real-wrist session surfaced five issues
(user report, 2026-07-17, verbatim numbering):

1. **Live HR shows nothing** — `--` everywhere, in Live HR view and during intervals.
2. **Boxing doesn't progress time** — warm-up / work / rest all show the same static time.
3. **Lifts default to kg** — and there is no setting on the watch to change to lbs.
4. **Lifts flow is wrong** — no way to save / cancel / exit normally; should say
   **"Strength"** not "Lift" and follow the on-phone flow: warm-up → one or more
   lifts → cool-down, with Save or Cancel available at any time.
5. **Cardio is missing** — need Run, Walk, Cycle (outdoor **and** indoor), Swim with a
   simple lap counter, plus Other — in addition to existing HIIT and Boxing — so the
   watch alone covers a full fitness life ("watch-only").

**Goal of v3:** the user can leave the phone at home for any typical workout —
strength, run, walk, ride, swim, HIIT, boxing, other — and lose nothing: correct
live HR, correct timers, correct units, a normal save/cancel lifecycle, and every
workout landing in HealthKit (rings) and back on the phone (history/coach).

## Root causes (all confirmed in code — see 01-bugfixes.md for detail)

| # | Symptom | Root cause | File |
|---|---------|-----------|------|
| 1 | No live HR anywhere | `requestHRAuthorization()` gates on `authorizationStatus(for: heartRate)` — a **share** (write) status that was never requested and never will be granted → returns not-authorized → `startWorkout()` bails → **no `HKWorkoutSession` ever starts** → no HR callbacks | `WatchWorkoutManager.swift:69-80,94-101` |
| 2 | Static interval time | `TimelineView` closure never reads `timeline.date`, and `.onChange(of: Date())` sits **outside** the timeline closure so it never fires → `runner.now` is never advanced past init | `WatchIntervalView.swift:33,117` |
| 2b | (latent) Workouts never reach HealthKit | `stopWorkout()` ends collection but **never calls `builder.finishWorkout()`** → no `HKWorkout` is saved → no rings credit, and the phone's HealthKit ingest (FR-3) never sees watch workouts | `WatchWorkoutManager.swift:104-116` |
| 3 | kg only, no setting | `"%.0f kg"` hard-coded; crown/chips step in kg; watch has no Units setting and never receives the phone's `AppSettings.unit` | `WatchStrengthView.swift:141` |
| 4 | Broken lift lifecycle | Session auto-created in `.onAppear` (orphans on back-swipe); "Done" toolbar button only exists on the picker step; no cancel/discard path; no warm-up/cool-down stages; title "Lift" | `WatchStrengthView.swift:36-44,250-257` |
| 5 | No cardio | Launcher only offers Live HR / Lift / HIIT / Boxing; `activityType(for:)` already maps run/walk/cycle/swim/other but nothing starts them; config hard-codes `.indoor` | `WatchRootView.swift:16-32`, `WatchWorkoutManager.swift:165-168` |

## Design principles (carried from v2, plus new)

- **Glanceable, single-screen, linear**; Crown for fine control, chips for coarse.
- **Reuse pure engines** — `IntervalRunner`, `WorkoutClock`, `RestTimerModel`,
  `WorkoutRepository`, `Format`, `MeasurementUnitPreference` all exist and are tested.
  New logic goes in `CadenceFeatures` (headless `swift test`), views stay thin
  (test-pyramid guardrails already enforce this for watch files).
- **Match Apple Workout muscle memory** for cardio: swipe-left controls page
  (End / Pause / Lock / Lap), metrics page center. Users already know this grammar.
- **HealthKit is the cardio sync channel.** The phone already ingests
  watch-recorded `HKWorkout`s + HR (FR-3) — cardio needs **no new WC schema**,
  it just needs the watch to actually *save* the workout (bug 2b). Strength keeps
  the richer `transferUserInfo` path (sets/reps/weight have no HK schema).
- **NFR-2 throughout**: color never alone, VoiceOver labels, Dynamic Type.

## Phased rollout (one branch + PR each; detail in 05-rollout.md)

| Phase | Branch | Delivers | Depends on |
|---|---|---|---|
| **W1 — Make it live** | `watch/w1-hr-timer-save` | Fix HR auth gate; drive `runner.now` from the timeline; finish/save `HKWorkout`s; Live HR quick-session | — |
| **W2 — Units** | `watch/w2-units` | lb/kg preference on watch (locale default → **lbs** in US), Settings row, phone→watch sync via `applicationContext` | — |
| **W3 — Strength flow** | `watch/w3-strength-flow` | "Strength" naming; session home; warm-up sets + cool-down timer; Save/Cancel anywhere; summary; discard sync | W2 |
| **W4 — Cardio suite** | `watch/w4-cardio` | Run/Walk/Cycle (indoor+outdoor), Swim + lap counter, Other; metrics views; controls page; summary + HK save | W1 |
| **W5 — Polish (backlog)** | `watch/w5-polish` | Resume, Smart Stack complication, GPS route builder, auto-pause | W3, W4 |

W1+W2 are independent and can land in either order; W3 stacks on W2, W4 on W1.
W5 is explicitly backlog — not required for "watch-only".

## Plan sections

- `01-bugfixes.md` — W1: HR, timer tick, HKWorkout save (+ Live HR quick session)
- `02-units.md` — W2: lb/kg on the wrist
- `03-strength-flow.md` — W3: phone-parity strength lifecycle
- `04-cardio.md` — W4: run/walk/cycle/swim/other
- `05-rollout.md` — consolidated schema deltas, migration safety, testing, verification
- `decisions.md` — open decision sheet (needs user answers before W3/W4 start)
- `watch-mockups.html` — full set of screen mockups, one per view (open in browser)

## Verification (every phase)

1. `cd CadenceCore && swift test` — the reliable gate; all new models headless-tested.
2. `xcodebuild -scheme Cadence … build` — phone still builds with embedded watch.
3. `make watch-smoke` — the capped watch UI smoke (extended in W1 to assert the
   countdown actually advances — the regression test for bug 2).
4. `bash scripts/check-test-pyramid.sh` — watch view LOC budget + import ban.
5. **Real validation on device/TestFlight** — every one of these five reports came
   from real hardware; the simulator would not have caught 1, 2b, or swim water-lock.
6. Post-task checklist per CLAUDE.md (current_state.md, README, commit, merge, push, CI, SHA).
