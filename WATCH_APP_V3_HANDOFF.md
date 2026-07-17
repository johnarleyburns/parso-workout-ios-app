# Cladiron — Watch App v3 "watch-only fitness" (handoff for agentic coding)

**Plan: `plans/watch-app/2026-07-17/`** — read `00-overview.md` first, then the
section file for the phase you're implementing. **Mockups:
`plans/watch-app/2026-07-17/watch-mockups.html`** (open in a browser) — one
mockup per view; every screen you build must match its figure and caption.

All design decisions are **settled** (recorded verbatim in `00-overview.md`
§Decisions — D1–D8). Do not re-litigate them; do not invent new UX.

## What v3 delivers

Five field reports from the real watch, all root-caused in the plan:

1. Live HR never appears → broken HealthKit auth gate aborts every session
   (`WatchWorkoutManager.swift:69-80,94-101`).
2. Interval clock frozen → `runner.now` never advanced (`WatchIntervalView.swift:33,117`).
3. Lifts hard-code kg, no setting → W2 units.
4. No save/cancel lifecycle for lifts, wrong name → W3 "Strength" flow (+ partners).
5. No cardio → W4 Run/Walk/Cycle (indoor+outdoor, auto-pause), Swim + laps,
   Rowing, Other, HIIT/Boxing setup screen.

Plus latent bug 2b: `finishWorkout()` is never called, so **no watch workout has
ever been saved to HealthKit** — fixing this is what makes cardio sync free
(phone already ingests HK workouts, FR-3).

## Phase order, branches, dependencies

| Order | Branch | Plan file | Depends on |
|---|---|---|---|
| 1 | `watch/w1-hr-timer-save` | `01-bugfixes.md` | — |
| 2 | `watch/w2-units` | `02-units.md` | — (parallel with W1 ok) |
| 3 | `watch/w3-strength-flow` | `03-strength-flow.md` | W2 — **branch off W2** if unmerged (stacking rule, CLAUDE.md) |
| 4 | `watch/w4-cardio` | `04-cardio.md` | W1 — **branch off W1** if unmerged |

`05-rollout.md` has the consolidated contract deltas (WC keys, HK share types,
UserDefaults), migration-safety notes, and the definition of done. W5 is backlog
— do not build it.

## Ground rules (repo law — CI enforces most of these)

- **Logic in `CadenceFeatures`** (Foundation+SwiftData+Observation only — no
  SwiftUI imports); watch views are thin renderers. New pure models per plan:
  `WatchAuthPolicy`, `WeightIncrement`, `WatchStrengthFlowModel`,
  `WorkoutConfigurationSpec`, `CardioMetricsModel`, `AutoPauseDetector`,
  `IntervalSetupModel`. Coverage grows in `swift test` (~74 new cases planned),
  **never** in the XCUITest suite (capped).
- Watch view files ≤400 LOC (`scripts/check-test-pyramid.sh`); split
  `WatchStrengthView` as specced in `03-strength-flow.md`.
- Schema: **additive only.** No SwiftData changes are needed anywhere in v3 —
  if you think you need one, stop and re-read the plan.
- WC payload discipline: `transferUserInfo` for sets/discards,
  `updateApplicationContext` for settings, `sendMessage` only for live HR when
  reachable. All new keys/actions are additive (old phone ignores them).
- Every user-visible weight/distance/pace goes through the unit preference —
  no `"kg"`/`"km"` literals (grep is an acceptance check).
- NFR-2: VoiceOver labels + Dynamic Type on every new view; color never the
  only signal.
- Per phase: verify (`cd CadenceCore && swift test`, phone `xcodebuild` build,
  `make watch-smoke`, pyramid script) **before** committing, then follow the
  CLAUDE.md post-task checklist (current_state.md, README if user-visible,
  commit w/ trailer, merge, push, watch CI, report SHA).
- Simulator can't validate HK auth, GPS, water lock, or auto-pause — say so in
  the report and list what needs on-device/TestFlight confirmation.

## Paste-ready prompts (one per phase)

### W1
> Implement phase W1 of `plans/watch-app/2026-07-17/` (read `00-overview.md` +
> `01-bugfixes.md`). Branch `watch/w1-hr-timer-save` off main. Fix the HealthKit
> auth gate (gate on workoutType share only, expanded share set per plan), drive
> `runner.now` from the TimelineView date in `WatchIntervalView` (delete the dead
> outer `.onChange(of: Date())`), implement state-driven
> `endCollection→finishWorkout` teardown as `stopWorkout(save:)`, and add the
> Live HR Start/Stop discarded monitoring session. Extend the existing watch
> smoke test to assert the countdown text changes after 2 s. Match the W1 figures
> in `watch-mockups.html`. Verify per the handoff ground rules, then run the
> post-task checklist.

### W2
> Implement phase W2 of `plans/watch-app/2026-07-17/` (read `00-overview.md` +
> `02-units.md`). Branch `watch/w2-units` off main. Add `WeightIncrement` to
> CadenceFeatures with headless tests; instantiate `AppSettings` on the watch
> seeded from locale (US → pounds); add the Settings Units row + picker per the
> W2 mockup figures; sync all four settings phone→watch via
> `updateApplicationContext` and unit edits watch→phone via `set_unit`; route all
> watch weight display/steps through `Format` + the preference (no `kg`
> literals). Verify, then run the post-task checklist.

### W3
> Implement phase W3 of `plans/watch-app/2026-07-17/` (read `00-overview.md` +
> `03-strength-flow.md`). Branch `watch/w3-strength-flow` off W2 (or main if W2
> merged). Build `WatchStrengthFlowModel` (lazy session create, warm-up flag
> default OFF, cool-down, Finish/Cancel semantics, roster rotation) with the full
> headless transition-table tests; split the view into home/keypad/partners/rest/
> cooldown/summary files per plan; rename all user-visible "Lift" → "Strength";
> add `discard_session` + `performed_by` handling on the phone and
> `partners.recent` in the context push. Match the W3 figures in
> `watch-mockups.html`. Verify, then run the post-task checklist.

### W4
> Implement phase W4 of `plans/watch-app/2026-07-17/` (read `00-overview.md` +
> `04-cardio.md`). Branch `watch/w4-cardio` off W1 (or main if W1 merged). Build
> `WorkoutConfigurationSpec`, `CardioMetricsModel`, `AutoPauseDetector`, and
> `IntervalSetupModel` in CadenceFeatures with headless tests first; rework the
> launcher (Strength hero + Run/Walk/Cycle/Swim/HIIT/Boxing/Rowing/Other/Live
> HR/Settings); add setup screens (Outdoor|Indoor remembered per type; swim
> Pool|Open with 25/50 presets + crown fine-tune; HIIT/Boxing rounds·work·rest
> via `IntervalPlan.custom`), type-specific live-metrics views, the swipe-left
> controls page (End·Pause·Lock·Lap), auto-pause for outdoor types, and the
> summary with Save/Discard. Match the W4 figures in `watch-mockups.html`.
> Verify, then run the post-task checklist and list what needs on-device
> validation.

## Done = the "definition of done" in `05-rollout.md`
A week of training with the phone in a drawer: strength w/ partners in lbs,
custom boxing rounds, auto-pausing outdoor run, indoor cycle, 50 yd pool swim,
rowing erg — every workout in rings + phone history, cancelled workouts leaving
zero residue.
