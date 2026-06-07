# §05 — Cardio: Outdoor GPS (Run / Walk / Cycle)

> Addresses field note **#3 (running/walking/cycling are outdoor GPS path-traced
> workouts, each with its own screen)**. Builds on the existing `CardioRecorder`,
> `LocationTracker`, and `CardioMath`, and on the session engine (§02).

Decisions applied: #17 (Run/Walk/Cycle get GPS+map; indoor = timer-only), #18
(MapKit, no new deps), #19 (auto-pause off by default).

---

## Problem (from the field test)

"Running/walking/cycling which are outdoor GPS path-tracing outdoor workouts each
with their own screen." Today there is one generic `RecordCardioView` live screen
shared by all cardio types, with **no map** — just numeric metric tiles. There's
no path tracing surfaced live, and backgrounding stops the timer (§02).

## What the code does today

- `CardioRecorder.swift` — already records GPS via `LocationTracker` for
  `type.usesGPS` (run/cycle/walk), accumulates `distanceMeters`, computes `pace`,
  `zone`, `calories`, HR samples. `end()` returns a `CardioWorkoutSummary` with
  `route` fixes.
- `LocationTracker.swift` — exists (CoreLocation); start/stop, `distanceMeters`,
  `fixes`.
- `CardioMath` — `paceSecPerKm`, `hrZone`, `zoneName`, `estimateCalories`,
  `formatPace`.
- `RouteSample` model + `saveRecordedCardio` persist the route; `CardioDetailView`
  shows saved cardio (check whether it already renders a map).
- `RecordCardioView` — generic live screen (numeric only), 1 Hz foreground timer
  (stops in background — §02 fixes via wall-clock).

So the **data pipeline already exists**; this section is mostly a **purpose-built
GPS screen with a live map + true background tracking**.

## Research / platform signal

- **MapKit** (`Map`, `MapPolyline` in SwiftUI) renders the live route with **zero
  new dependencies** (NFR-6) — decision #18.
- Background route capture during a call/pocket requires the **location**
  background mode + `allowsBackgroundLocationUpdates` and a "When In Use" (or
  Always) authorization with a clear purpose string (NFR-3). This is what makes
  the "continue across interruptions" requirement real for outdoor cardio
  (§02 §B notes GPS is the one type needing a true background mode).

---

## Design

### A. `OutdoorCardioView` (Run / Walk / Cycle)

Launched from the type picker (§02) for `.run/.walk/.cycle`. A single screen
configured by type (icon, default HR zone basis, calorie model already keys off
`CardioType`). Layout, legible at a glance:

```
┌──────────────────────────────┐
│  Run                00:24:10  │  ← type + elapsed (WorkoutClock)
│ ┌──────────────────────────┐ │
│ │        live map          │ │  ← MapKit, route polyline grows live,
│ │     ╭─╮   ____            │ │     camera follows current location
│ │    ╱   ╲_╱                │ │
│ └──────────────────────────┘ │
│  3.42 km        5:48 /km     │  ← big distance + pace
│  HR 152 · Z3    312 kcal     │
│  [ Connect HR Strap ]        │  ← reuses existing strap flow
│                              │
│   [ Pause ]      [ End ]      │
└──────────────────────────────┘
```

- **Big distance + pace** (low-vision: large rounded numerals, already the style
  in `RecordCardioView`).
- **Live map** with growing `MapPolyline` from `LocationTracker.fixes`; camera
  follows the user; a "recenter" control. Honors Reduce Motion (no needless
  camera animation).
- HR / zone / calories tiles reuse `CardioMath` + the existing strap connect
  flow.
- **End** → `recorder.end()` → `saveRecordedCardio` + summary `HKWorkout` (already
  wired in `RecordCardioView.endWorkout`); then route shows in `CardioDetailView`
  / History.

### B. Indoor / non-GPS (decision #17)

Run/Walk/Cycle here are **outdoor GPS**. Indoor variants (treadmill, indoor bike)
are **not** separate screens in v1 — they fall under "Other" → the generic
timer+HR live screen (today's `RecordCardioView` body, minus the picker). No map,
no GPS. Revisit dedicated indoor screens later.

### C. Background & interruptions (ties to §02)

- Enable **location background mode** + `allowsBackgroundLocationUpdates = true`
  and `pausesLocationUpdatesAutomatically` (configurable) in `LocationTracker`,
  guarded by authorization.
- Elapsed is **wall-clock** (`WorkoutClock`, §02), so a phone call doesn't lose
  time; route keeps accumulating in the background.
- **Auto-pause (decision #19):** off by default; a Settings toggle. When on, use
  speed threshold from `LocationTracker` to pause/resume the clock (so red
  lights/rests don't tank pace). Off = manual Pause only.
- The §02 idle watchdog treats GPS movement / HR samples as activity, so an
  outdoor workout won't false-trigger the 10-min auto-terminate while you're
  moving; a truly stopped, forgotten workout still gets the prompt.

### D. GPS accuracy / battery (NFR-7)

- Settings: GPS accuracy tier (high / balanced) feeding
  `LocationTracker.desiredAccuracy`. Default balanced; "high" for racing.
- Show a brief "GPS weak" banner when horizontal accuracy is poor (UC-3 alt 2a)
  and keep recording at reduced accuracy.

---

## Data-model deltas

**None new.** `CardioWorkout` + `RouteSample` + `HRSample` already model
everything; `CardioRecorder`/`saveRecordedCardio` already persist route + HR.
(`WorkoutSession.endedAt` from §02 is strength-only; cardio already has `end`.)

## Implementation steps

1. **`OutdoorCardioView`**: type-configured GPS screen with live `Map` +
   `MapPolyline` bound to `LocationTracker.fixes`; big distance/pace; reuse strap
   flow + `CardioRecorder`.
2. **Route the type picker** (§02): `.run/.walk/.cycle` → `OutdoorCardioView`;
   indoor/other → generic timer screen.
3. **Background location:** add the capability/Info.plist mode + purpose string;
   `LocationTracker.allowsBackgroundLocationUpdates`; wall-clock elapsed (§02).
4. **Auto-pause** setting + speed-threshold logic (off by default).
5. **GPS accuracy** setting + weak-signal banner.
6. **CardioDetailView**: ensure it renders the saved route on a map (add if
   missing) so finished outdoor workouts show their path (FR-5.3).
7. Remove the type grid from `RecordCardioView` (picker now owns type choice);
   keep its live body for "Other".

## Testing

- **Unit (swift test):** `CardioMath` pace/zone/calorie already covered; add
  tests for auto-pause speed thresholding (pure function) and that route fixes
  map to a polyline coordinate list correctly.
- **UI (iPhone + iPad):** start a Run via picker → assert map element + elapsed +
  distance identifiers present; Pause/Resume toggles; End saves and the workout
  appears in History with a route. (Simulator GPS via a `.gpx` route in the test
  scheme; FakeProviders already exist for HR.)
- **Background:** with an injected fake location stream, deactivate/activate the
  app → elapsed and distance advanced (wall-clock + buffered fixes).
- **Accessibility:** map has an accessibility summary ("route, 3.4 km"); numbers
  large; honors Reduce Motion (no camera chase animation when set).

## Open questions (resolved)

- GPS for Run/Walk/Cycle; indoor = timer-only "Other" (decision #17). ✔
- MapKit, no new deps (decision #18). ✔
- Auto-pause off by default, toggle (decision #19). ✔
