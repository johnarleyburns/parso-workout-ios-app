# Cladiron Apple Watch App — Plan

## Context

We're finally building the Apple Watch companion for Cladiron (internal codename
Cadence). A prior attempt (FR-8) is shelved and unreliable — this plan replaces it
with a robust, standalone, wrist-first workout app that preserves what the user
loves on the phone (partner training, mid-workout exercise swaps, science-cited
interval timing) **without ever picking up the phone**.

**The gap we're filling** (confirmed by market review — Strong/Hevy log strength
from the wrist but don't program; Intervals Pro/boxing timers do color-coded rounds
but aren't a real logger): nobody combines a **full-screen, color-coded HIIT/Boxing
round timer** with **standalone strength logging that supports partners and smart
exercise swaps**, all backed by cited science. That's Cladiron's wedge.

### Why the prior attempt was unreliable (root causes we must fix)
1. **The watch app was never embedded in the phone app** — the `Cadence` target has
   no "Embed Watch Content" (`PBXCopyFilesBuildPhase`) and an empty `dependencies`
   list, so the `.app` never ships in the archive. *(This alone meant it never
   reached a device.)*
2. **Phone side hard-gated off**: `AppModel.liveWatchHREnabled = false`
   (`Cadence/Cadence/App/AppModel.swift:22`).
3. **Watch code is a stub + crude relay**: `ContentView.swift` is the "Hello, world!"
   template; `WatchWorkoutManager.swift` polls HR on a 1 s `Timer`, calls
   `requestAuthorization` completion `true` unconditionally, and drops
   `sendMessage` silently when unreachable.
4. Empty `didCollectDataOf`/`didCollectEvent` callbacks — HR wasn't event-driven.

### The big asset: almost all logic is already pure and shared
Both app targets depend on the `CadenceCore` SwiftPM package (`CadenceCore` +
`CadenceFeatures`). The watch links the **same** code — we reuse, not reimplement:

| Need | Reuse (already pure, `swift test`-covered) |
|---|---|
| Interval phases/plan | `CadenceCore/…/IntervalPlan.swift` (`IntervalPlan`, `IntervalPhase`, `IntervalPhaseKind`, factories `tabata`/`norwegian4x4`/`boxing`/`gibala`/`sit`/`rehit`/`tenTwentyThirty`) |
| Color signal | `FullScreenColorState` + `IntervalSignal.colorState(phase:remaining:)` |
| Interval runner | `CadenceFeatures/IntervalRunner.swift` (`colorState`, `phaseRemaining`, `skipPhase`, `addTime`) |
| Drift-free timing | `CadenceCore/WorkoutClock.swift` (wall-clock, survives backgrounding) |
| Cue timing | `CadenceFeatures/IntervalCueDecider.swift` (30 s warning + final-3 s ticks) |
| Strength model | `CadenceCore/Models.swift` (`WorkoutSession`, `SetEntry`, `Exercise`, `Person`) |
| Set logging + swap | `CadenceCore/WorkoutRepository.swift` (`addSet`, `changeExercise`, `findOrCreatePerson`) |
| Partners | `CadenceCore/SessionRoster.swift` (scoped roster, rotation, `isOwnerSet` isolation) |
| Smart Start | `CadenceCore/RecommendationEngine.swift` (`pickRoutine`) |
| Active session | `CadenceFeatures/ActiveWorkoutModel.swift`, `RestTimerModel.swift` |
| HR parsing | `CadenceCore` `HeartRateParser` / `HRSampling` |

**One net-new pure engine:** a strength `ExerciseSubstitution` ranker (doesn't exist
yet) — seeds smart swaps from movement pattern/family + body parts + equipment +
recents. Built in `CadenceCore`, `swift test`-covered, and wired into the phone's
swap picker too (bonus win).

## Decisions (confirmed with user)
- **Standalone + WatchConnectivity sync.** Watch has its **own local SwiftData store**
  (no CloudKit — avoids the documented SwiftData+CloudKit watch crash 30–60 s into an
  extended-runtime session). Runs workouts fully offline; sets sync to the phone via
  `transferUserInfo` (guaranteed background delivery), merged idempotently by `UUID`
  (FR-9.2). Phone stays system-of-record + analysis surface.
- **HR: both watch-native AND direct BLE strap in v1.** Port the `0x180D` CoreBluetooth
  chest-strap manager to run **on the watch** (reusing the pure `HeartRateParser`), plus
  the watch's own `HKLiveWorkoutBuilder` high-frequency stream. **Never** read the slow
  Fitness-app/HealthKit samples for live HR. A persisted `HRSource` (`.appleWatch` /
  `.bluetooth`) is user-picked, defaults to `.appleWatch`, remembered, always changeable.
- **Intervals first.** Foundation + HR, then the color-coded HIIT/Boxing timer (the
  user's biggest felt gap), then strength, then partners + swap.

## Watch UX principles (from HIG + gym-reality research)
- **Glanceable, single-screen, linear.** ≤3 glyph buttons per row; big tap targets.
- **Digital Crown for fine control** (weight, reps, +time), **quick chips** for coarse.
- **Whole-screen color = the interval signal**, readable across the room; meaning always
  carried by color **+ label + icon** (never color alone — NFR-2), with colorblind and
  Reduce-Motion variants.
- **Sweaty-hand resilience**: side-button/Crown controls, **water-lock during runs**,
  confirm destructive taps.
- **Always-On Display**: update ≤1 Hz in Always-On; hide sub-seconds.
- **Haptics-first cues** so the user doesn't need to look (`WKInterfaceDevice`).

## HTML mockups
All ~20 watch screens are rendered in `watch-mockups.html` (open in a browser) —
also published as a review artifact. Screens: Launcher · Interval setup (HIIT & Boxing) ·
Interval running (Work/Warning/Imminent/Rest, Boxing round) · Live HR & zones ·
Routine picker · Strength card · Weight/Reps keypad · Rest timer · Partner rotation ·
Swap (smart substitutes) · Workout summary · HR-source picker · Settings · Handoff ·
Smart Stack complication.

## Phased rollout (one branch + PR each, verified by `swift test` before merge)

| Phase | Branch | Delivers |
|---|---|---|
| **0 — Foundation** | `watch/00-foundation` | Embed watch app in phone archive; link `CadenceCore`/`CadenceFeatures`; replace template root with launcher; create the ONE watch simulator by name; Makefile `watch-smoke`; extend pyramid guardrail; ungate phone WC. |
| **1 — HR engine** | `watch/01-hr` | Event-driven `HKLiveWorkoutBuilder` HR + direct BLE strap on watch; `HRSource` picker (persisted); live-HR relay to phone; Live HR/zone view. |
| **2 — Intervals** | `watch/02-intervals` | Full-screen color-coded HIIT/Boxing timer (reuse `IntervalRunner`); watch haptic cue player; compact protocol picker + Crown steppers; water-lock. **First headline slice.** |
| **3 — Strength** | `watch/03-strength` | Standalone wrist logging: routine picker (`pickRoutine`), exercise card, Crown/chip weight+reps keypad, rest timer, local store + `transferUserInfo` sync (merge by UUID). |
| **4 — Partners + Swap** | `watch/04-partners-swap` | Partner rotation (`SessionRoster` + `performedBy`); new `ExerciseSubstitution` ranker → smart swap screen (`changeExercise`); also wired into phone swap. |
| **5 — Handoff + polish** | `watch/05-handoff` | Two-way live handoff (`updateApplicationContext`); Smart Stack complication / Live Activity; extended-runtime hardening; settings sync; TestFlight verification. |

Phases stack in order (each depends on the prior); branch each off its predecessor.

## Per-phase detail

### Phase 0 — Foundation (make it actually ship)
- **Embed**: add an "Embed Watch Content" `PBXCopyFilesBuildPhase` (dstSubfolderSpec
  Watch) to the `Cadence` target + a target dependency on the watch app. This is the
  single most important fix. Verify the archived `.xcarchive` contains
  `Watch/…app/PlugIns`.
- **Link** `CadenceCore` + `CadenceFeatures` into `Cadence Watch App Watch App` target.
- **Root**: delete `ContentView.swift` template; new `WatchRootView` launcher
  (Start Lift · HIIT · Boxing · Resume · Settings) as a glanceable `List`.
- **Simulator**: create exactly one — `xcrun simctl create "Apple Watch Series 10 (46mm)"
  <Series-10-46mm devicetype> <watchOS 11.1 runtime>`. There are currently **zero**
  watch devices instantiated and one runtime (watchOS 11.1). Pin in `Makefile`:
  `WATCH_SMOKE_DEST ?= platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)`
  (mirrors the existing `SMOKE_DEST` iPhone-16-by-name pattern). Add `make watch-smoke`
  (build-for-testing + `test-without-building`, serial, no clones, no retries).
- **CI / pyramid**: `.github/workflows/ios.yml` keeps `core-tests` (`swift test` +
  `check-test-pyramid.sh` + `check-no-network.sh`) as the gate. **No watch simulator in
  CI.** `check-test-pyramid.sh` extended: watch UI-smoke cap (≤3 `func test`, "boot +
  start/stop" only), 400-LOC ceiling for watch view files, import ban still applies
  (watch view-models live in `CadenceFeatures`). `testflight-build` archives scheme
  `Cadence` — now ships the embedded watch app.
- **Ungate**: flip `AppModel.liveWatchHREnabled` on (behind a real capability check).

### Phase 1 — HR engine + source picker (native + BLE)
- Rewrite `WatchWorkoutManager` → `WatchWorkoutSessionController`: `HKWorkoutSession` +
  `HKLiveWorkoutBuilder`, **event-driven** `workoutBuilder(_:didCollectDataOf:)` for
  `.heartRate` (no polling `Timer`); correct auth (respect grant, surface denial);
  runs in background + Always-On.
- `WatchHeartRateBLE`: CoreBluetooth central on watchOS for `0x180D`/`0x2A37` (+ battery
  `0x180F`/`0x2A19`), reusing pure `HeartRateParser`. Mirror the phone's reconnect/backoff.
- `HRSource` enum in `CadenceCore` + persisted setting (default `.appleWatch`,
  remembered, changeable); first-run prompt. `WatchHRProvider` (pure, in
  `CadenceFeatures`) is a state machine over an injected sample stream → **headless
  tested** (source switching, dropout buffer, zone mapping).
- Relay live HR watch→phone via `sendMessage` **only when reachable** (feeds existing
  `HeartRateMonitor.injectExternalBPM`), so the phone HR band still works during handoff.
- Views: Live HR + zone color; HR-source picker (watch Settings + phone `HRMSettingsView`).

### Phase 2 — Intervals on the watch (HIIT/Boxing) — first user-facing win
- `WatchIntervalView`: whole-screen background = `FullScreenColorState` → `Color`,
  re-authored for watchOS (work=green, warning=yellow, imminent=flash yellow↔orange,
  rest=red, neutral=blue; colorblind=blue/purple/gray; Reduce-Motion=solid). Large
  monospaced countdown + phase label + "Round x/N" + BPM + total-left. `TimelineView`
  Always-On aware (≤1 Hz). Drives the reused `IntervalRunner`.
- `WatchIntervalHaptics` (`WKInterfaceDevice`) driven by the pure `IntervalCueDecider`:
  phase-change (work=success, rest=warning, warmup=light), 30 s work warning, final-3 s
  ticks (haptic only), completion. Boxing = stronger "bell" pattern; HIIT = soft.
- Setup: compact protocol picker (Tabata / Norwegian 4×4 / Gibala / SIT / 10-20-30 /
  REHIT / Boxing / Custom) using the same `IntervalPlan` factories; Crown steppers for
  custom rounds/work/rest (boxing defaults 8×180/60, HIIT 8×30/30). Or receive a plan
  via handoff.
- Controls: tap = pause/resume; Crown = +1 min (`addTime`); skip (confirm) / end via
  side buttons; **water-lock** during the run. Concurrent `HKWorkoutSession` for HR +
  background + summary write-back. Cite the same protocol sources (`citationIds`).

### Phase 3 — Strength logging (standalone)
- Watch-local `ModelContainer` (CadenceCore models, **no CloudKit**). Bundle a compact
  exercise catalog on the watch.
- Start: routine picker from `RecommendationEngine.pickRoutine` (Smart Start) preset
  list, or handoff.
- Exercise card: name, previous set ("135 × 8 last"), big weight + reps, Log Set.
  Weight = Crown (fine) + chips (±2.5/5/plate); reps = Crown + chips. Reuse
  `SetEntry.effectiveLoadKg` accounting (send raw weight + accounting mode).
- Rest timer: reuse `RestTimerModel`; auto-start after log; haptic on complete.
- Log via a watch mirror of `WorkoutRepository.addSet` into the local store; enqueue set
  payloads to the phone via `transferUserInfo` (merge by `UUID`). `ActiveWorkoutModel`
  mirror on watch (exactly one active session). Finish → summary + `HKWorkout` write-back
  + final sync. New pure view-models (`WatchKeypadModel`, `WatchSyncMerger`) headless-tested.

### Phase 4 — Partners + Swap
- Partners: reuse `SessionRoster`; `performedBy` picker on the keypad that **rotates
  through the ordered roster after each saved set** (mirrors phone); add partner from a
  recent list; new name via Scribble/dictation. Partner sets stay out of PRs/Health
  (`isOwnerSet`, already enforced).
- Swap: **new pure `ExerciseSubstitution` ranker** in `CadenceCore` — ranks candidates by
  shared movement pattern/family + covered body parts + available equipment + user
  recents; returns top ~6. Watch swap screen shows ranked substitutes + recents → pick →
  `WorkoutRepository.changeExercise`. Wire the same ranker into the phone's
  `ExercisePickerView` swap mode (bonus). `swift test` for ranking correctness.

### Phase 5 — Handoff + complications + polish
- Two-way live handoff via `updateApplicationContext` (start on phone → "Continue on
  Watch", and back). Resilient state snapshot (session id + planned names + partner ids +
  last set), not live-only `sendMessage`.
- Smart Stack Live Activity / complication: current interval phase + countdown, or active
  set + rest timer.
- Extended-runtime session hardening; Always-On polish; water-lock; settings sync
  (HR source, colorblind, haptics). Verify TestFlight archive embeds the watch app; run
  the single on-device smoke locally.

## Reliability rules baked in (lessons from the shelved attempt)
1. Embed the watch content (the missing archive phase).
2. **Event-driven** HR via `HKLiveWorkoutBuilder` callbacks; honest HealthKit auth.
3. WC discipline: `transferUserInfo` (guaranteed) for sets, `updateApplicationContext`
   for latest state, `sendMessage` **only** for live HR when reachable — never silent-drop.
4. Wall-clock `WorkoutClock` timing for drift-free interval mirroring.
5. **No SwiftData+CloudKit on watch.**
6. Always-On ≤1 Hz + a properly managed `WKExtendedRuntimeSession`.

## Testing methodology (per user + CLAUDE.md pyramid)
- **Bulk = headless `swift test`** on the Mac toolchain, in `CadenceFeatures`/`CadenceCore`:
  `WatchHRProvider`, watch interval driver wrapper, `WatchKeypadModel`, `WatchSyncMerger`,
  `ExerciseSubstitution`, HR source switching, WC merge-by-UUID. Copious — this is where
  coverage grows.
- **Exactly ONE watchOS simulator**, created and pinned **by name**
  ("Apple Watch Series 10 (46mm)"), never by UUID. **ONE** watch UI smoke test only:
  launch → start a workout → stop. `make watch-smoke`, **local only**.
- **No watch simulator tests in GitHub Actions** — CI runs `swift test` + guardrails only,
  and archives `Cadence` (with embedded watch) for TestFlight. Real testing = TestFlight.
- `check-test-pyramid.sh` extended: watch UI-smoke cap, watch-view 400-LOC ceiling,
  `CadenceFeatures` import ban (watch view-models obey it).

## Verification (end-to-end)
1. `cd CadenceCore && swift test` — all new pure engines green (this is the reliable gate).
2. `xcodebuild -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' build`
   — phone app still builds with the embedded watch target.
3. `make watch-smoke` — the single watch UI smoke (launch → start → stop) on the one
   named simulator.
4. Archive scheme `Cadence`; confirm the `.xcarchive` embeds `Watch/…app` (the fix for #1).
5. `bash scripts/check-test-pyramid.sh` + `check-no-network.sh` green.
6. Post-task checklist per CLAUDE.md: update `current_state.md`, README, commit per
   phase, merge to `main`, push, monitor CI, report SHA + status.
7. **Real validation on TestFlight** (simulator is unreliable for watch, per user).
