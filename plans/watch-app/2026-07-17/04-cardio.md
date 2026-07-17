# W4 — Cardio suite: Run · Walk · Cycle (indoor/outdoor) · Swim + laps · Rowing · Other

Fixes user report **5**: the watch must cover typical cardio so the phone can
stay home — Run, Walk, Cycling (outdoor **and** indoor), Swim with a simple lap
counter, Rowing (D6), and Other, alongside the existing HIIT and Boxing (which
gain a rounds/work/rest setup screen, D8). Outdoor run/walk/cycle auto-pause
like Apple Workout (D7).

## What the code does today

- `WatchWorkoutManager.activityType(for:)` already maps
  run/walk/cycle/swim/rowing/other → `HKWorkoutActivityType`
  (`WatchWorkoutManager.swift:201-213`) — but nothing in the UI starts them.
- `beginSession` hard-codes `config.locationType = .indoor` (`:168`) — wrong for
  outdoor run/ride/walk (kills distance accuracy + any future route).
- `CardioType` in CadenceCore already has `run, cycle, swim, walk, rowing, other`
  with display names, symbols, and `usesGPS` (`Models.swift:765-795`) — the menu
  is a pure reuse.
- The phone already ingests watch-recorded `HKWorkout`s + HR (FR-3) — **once W1
  makes the watch actually save workouts, cardio history syncs for free.** No new
  WC schema needed for cardio.

## Research signal
- Apple Workout's grammar is the muscle memory to match: **swipe-left controls
  page** (End · Pause · Water Lock · Lap/Segment), metrics center. Vertical
  paging via Crown on watchOS 10+.
- Swimming sessions **auto-enable Water Lock** and disable touch; lap interaction
  during a swim must therefore not depend on tapping. `HKWorkoutConfiguration`
  supports `swimmingLocationType` (.pool + `lapLength`, or .openWater); pool
  swims get **automatic lap/length events** from HealthKit — the honest "simple
  lap counter" is *display* of auto-counted lengths, with a manual +1 available
  when paused/unlocked (and the primary counter for open water… which has no laps
  — it shows distance instead). *(Decision D5, settled: auto with manual
  fallback; pool default 25 m/yd with a one-tap **50 m/yd preset** — plus Crown
  fine-tune — before the workout starts.)*
- Apple Workout auto-pauses outdoor runs when the runner stops; there is **no
  HealthKit API for this** — apps detect it themselves (pace collapse from
  distance deltas + CoreMotion activity) and call `session.pause()/resume()`.
  *(Decision D7, settled: ship it in W4 for outdoor run/walk/cycle, with haptic
  + on-screen "Auto-paused" state and a Settings toggle to disable.)*
- Distance/pace/energy come event-driven from `HKLiveWorkoutBuilder.statistics`
  for `distanceWalkingRunning` / `distanceCycling` / `distanceSwimming` /
  `activeEnergyBurned` — same callback we already use for HR.
- GPS route recording (`HKWorkoutRouteBuilder` + CoreLocation) is **not** required
  for distance (the watch fuses pedometer+GPS into the distance stats itself);
  routes are a W5 nice-to-have.

## Design

### Launcher (reworked — see mockups §Launcher)
Order: **Strength** (hero) · Run · Walk · Cycle · Swim · HIIT · Boxing · Rowing ·
Other · Live HR · Settings. All rows reuse `CardioType.displayName/symbol`.

### Setup screens
- **Run / Walk / Cycle**: one compact setup screen — segmented
  **Outdoor | Indoor** (remembered per type in UserDefaults;
  outdoor is the first-run default) → big Start. Maps to
  `config.locationType = .outdoor/.indoor` and the right activity type
  (`.running/.walking/.cycling`; indoor keeps the same activity type, location
  `.indoor` — HealthKit labels it "Indoor Cycle" etc. automatically). Outdoor
  setup notes auto-pause (D7).
- **Swim**: segmented **Pool | Open Water**; Pool shows lap-length **preset
  chips 25 | 50** (m/yd by unit pref) + Crown fine-tune for odd pools;
  remembered → `swimmingLocationType` + `lapLength` (D5). Open Water hides
  laps, shows distance.
- **Rowing**: no setup — straight in (`.rowing`, indoor) (D6).
- **Other**: no setup — straight in (`.other`, indoor).
- **HIIT / Boxing**: compact **setup screen** before the timer (D8): rounds ·
  work · rest fields, Crown-steppable, seeded from `hiitDefault()` (8×30/30) /
  `boxingDefault()` (8×180/60), last-used values remembered per kind; big Start.
  Builds the `IntervalPlan` via the existing `IntervalPlan.custom` factory path
  used by the phone. The interval timer itself is unchanged (fixed in W1).

### Live metrics view — `WatchCardioView` (one view, type-parameterized)
Center page, top-to-bottom (mockups §Cardio):
- elapsed (big, monospaced), then per-type metric rows:
  - Run/Walk: distance (mi/km by unit pref) · pace (min/mi | min/km, from recent
    distance delta) · HR+zone · active kcal
  - Cycle: distance · speed (mph/km-h) · HR+zone · kcal
  - Swim (pool): **lengths** (big) + distance · HR (optical HR is unreliable in
    water — show `--` gracefully) · kcal
  - Rowing: distance (where `distanceRowing` is available; availability-guarded)
    · **/500 m split** · HR+zone · kcal
  - Other: elapsed · HR+zone · kcal
- Outdoor run/walk/cycle: **auto-pause** — pace collapse + CoreMotion stillness
  → `session.pause()` + haptic + full-screen "Auto-paused" state; movement
  resumes automatically. Settings toggle (default ON, synced like other
  settings). Detection lives in a pure `AutoPauseDetector` (CadenceFeatures):
  inputs are timestamped distance samples + activity states, outputs
  pause/resume edges — fully headless-testable.
- Always-On: ≤1 Hz, seconds dimmed (same `isLuminanceReduced` handling as W1).

A new pure `CardioMetricsModel` (CadenceFeatures) owns formatting + pace/speed
derivation + zone mapping: inputs are raw statistics values; outputs are display
strings in the preferred unit (W2). Headless-tested; the view renders it.

### Controls page (swipe left — mockups §Controls)
2×2 grid, Apple-style: **End** (red) · **Pause/Resume** (yellow) ·
**Water Lock** · **+1 Lap** (swim, pool-manual fallback) / **Segment** (others,
W5 backlog — hidden in W4). End → confirm → summary.

### Summary + save
Duration · distance/laps · avg & max HR · kcal → **Save** (default; W1 teardown
writes the `HKWorkout` with `lapLength`/lap events and, for manual laps, a
`metadataKey` count) or **Discard**. After save: "Synced to iPhone via Health"
caption — sets the expectation that history appears on the phone after the next
HealthKit ingest, not instantly.

### Manager changes
`startWorkout(type:)` grows a `WorkoutConfigurationSpec` (pure struct in
CadenceFeatures: activity, location, swimming config) instead of the raw-string
switch + hard-coded `.indoor`. `didCollectDataOf` fans out to distance/energy
stats, not just HR. Swim sessions route lap events
(`workoutBuilderDidCollectEvent` → `.lap`/`.segment`) into `CardioMetricsModel`.

## Data-model deltas
- **None in SwiftData.** Cardio history reaches the phone through the existing
  HealthKit ingest (FR-3). The watch does not grow a cardio session model.
- New UserDefaults keys: `watch.cardio.location.<type>`, `watch.swim.lapLength`,
  `watch.cardio.autoPause` (default true), `watch.interval.<kind>.rounds/work/rest`
  (last-used setup values).
- `HKWorkout` metadata: manual-lap count key (additive, namespaced
  `guru.parso.cladiron.manualLaps`).

## Implementation steps
1. `WorkoutConfigurationSpec` + `CardioMetricsModel` + `AutoPauseDetector` +
   `IntervalSetupModel` (rounds/work/rest → `IntervalPlan.custom`, clamps,
   last-used persistence contract) in CadenceFeatures — headless tests first.
2. Extend `WatchWorkoutManager`: spec-driven config, distance/energy/lap
   collection, pause/resume (`session.pause()/resume()`), auto-pause wiring,
   water lock (`WKInterfaceDevice.current().enableWaterLock()`).
3. `WatchCardioSetupView` (run/walk/cycle/swim variants), `WatchIntervalSetupView`
   (HIIT/Boxing, D8), `WatchCardioView`, `WatchCardioControlsView` (`TabView`
   horizontal pages), `WatchCardioSummaryView`. Each file under the 400-LOC budget.
4. Launcher rework per mockups (incl. Rowing row).
5. Device verification matrix: outdoor walk (distance sane vs. phone; auto-pause
   at a stop light), indoor cycle (no GPS, kcal/HR flowing), pool swim (auto
   lengths at a real pool — or manual-lap fallback exercised), rowing (erg
   session), Other (elapsed+HR only), custom 3×120/45 boxing plan — each landing
   in Activity rings and phone history.

## Testing
- `swift test`: `CardioMetricsModel` (pace math incl. div-by-zero early samples,
  unit formatting both systems, zone mapping, lap accumulation auto+manual,
  open-water hides laps, /500 m split), `WorkoutConfigurationSpec`
  (type→activity/location matrix, swim configs incl. 25/50 presets),
  `AutoPauseDetector` (stop→pause edge, jitter debounce, resume edge, disabled
  flag), `IntervalSetupModel` (clamps, plan construction, last-used seeding).
- Watch smoke: still capped; extend the one start/stop smoke to start a Run
  instead of relying only on intervals *(only if it stays within the ≤3 cap —
  otherwise leave as-is; simulators can't do real distance anyway)*.
- Real device is the only meaningful gate for GPS/water/HR-in-water/auto-pause.

## Open questions
None — D5 (25/50 presets + manual fallback), D6 (Rowing in), D7 (auto-pause in
W4), D8 (interval setup in W4) all settled.
