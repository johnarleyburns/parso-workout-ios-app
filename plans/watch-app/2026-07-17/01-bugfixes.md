# W1 — Make it live: HR, timer tick, HealthKit save

Fixes user reports **1** (no live HR) and **2** (static interval time), plus the
latent **2b** (workouts never saved to HealthKit) that blocks the whole
"watch-only" premise.

---

## 1. Live HR shows nothing

### What the code does today
`WatchWorkoutManager.requestHRAuthorization()` (`WatchWorkoutManager.swift:69-80`):

```swift
try await store.requestAuthorization(toShare: [.workoutType()], read: types)
let status = store.authorizationStatus(for: hrType)   // ← share status of HR
hrAuthorized = (status == .sharingAuthorized)          // ← never true
```

`authorizationStatus(for:)` reports **write** permission. Heart rate was requested
as **read** only, so its share status stays `.notDetermined` forever →
`hrAuthorized == false` → `startWorkout()` hits `guard authorized else { isActive
= false; return }` (`:96-98`) and **silently aborts**. No `HKWorkoutSession` is
ever created, so:

- `HKLiveWorkoutBuilder` delegate callbacks never fire → `currentBPM` stays nil.
- The interval views run with no session behind them (they still render because
  the `IntervalRunner` is view-local).
- Nothing is relayed to the phone.

A second, independent gap: **Live HR from the launcher never starts a session at
all** — `LiveHRView` is display-only, and watchOS only streams optical HR
continuously inside a workout session. So even after the auth fix, tapping
"Live HR" from the menu would show `--` until some other workout is running.

### Research signal
- Apple: read authorization is intentionally opaque — an app *cannot* distinguish
  "read denied" from "no data yet". The correct gate is the **share** status of
  what you actually write (`HKObjectType.workoutType()`), and read is fire-and-forget.
- Continuous optical HR requires an active `HKWorkoutSession`; outside one, only
  periodic background samples exist (minutes apart). A "just watch my HR" surface
  therefore runs a real session and **discards** the workout on exit.

### Design
- **Fix the gate:** request `toShare: [workoutType, activeEnergyBurned, distanceWalkingRunning,
  distanceCycling, distanceSwimming]` (the types W4 will write), `read: [heartRate,
  activeEnergyBurned, distance*]`. Gate `startWorkout` on
  `store.authorizationStatus(for: .workoutType()) == .sharingAuthorized` **only**.
  If HR read was denied, the session still runs; the UI shows `--` with a one-line
  hint ("Enable Heart Rate in Settings → Health") instead of refusing to start.
- **Surface denial honestly:** launcher shows a small warning row if workout-share
  is denied, deep-linking the fix instructions (watch Settings → Health → Apps).
- **Live HR quick session:** the Live HR view gets a **Start / Stop** button that
  spins up an `.other` session purely for sensor streaming and calls
  `builder.discardWorkout()` on stop (never saved, no rings pollution). While any
  real workout is active, Live HR just mirrors it (as today).

### Implementation steps
1. Rework `requestHRAuthorization()` → `requestWorkoutAuthorization()`; correct
   share/read sets; return share-status of workoutType. Keep `hrAuthorized` but
   derive it from *whether HR samples arrive* (set true on first sample) for UI hints.
2. Remove the hard `guard authorized` abort for read types; keep it only for
   workout-share.
3. Add `startMonitoringSession()` / `stopMonitoringSession(discard: true)` to
   `WatchWorkoutManager`; `LiveHRView` gains Start/Stop + "not saved" caption.
4. Relay path unchanged (`sendMessage` when reachable).

### Testing
- Pure: extract the auth-decision into a tiny `WatchAuthPolicy` (input: share
  status, HR-sample-seen; output: canStart / hint) → `swift test`.
- Device: the real check. Simulator lies about HK auth; verify on hardware that
  first launch prompts, and BPM appears within ~5 s of starting Boxing.

---

## 2. Interval timer never advances

### What the code does today
`WatchIntervalView.swift:33`:

```swift
TimelineView(.periodic(from: Date(), by: 0.5)) { timeline in
    ZStack { … }          // ← never reads timeline.date
}
.onChange(of: Date()) { _, newDate in   // ← evaluated once, at body build
    runner.now = newDate
    …
}
```

Two compounding mistakes:
- The timeline closure **never reads `timeline.date`**, so SwiftUI has no
  dependency to invalidate — the content doesn't redraw on schedule.
- `.onChange(of: Date())` is attached to the *outer* view. `Date()` is captured
  when `body` is evaluated; since nothing observable changes, `body` is never
  re-evaluated and the closure **never fires**. `runner.now` stays at init time,
  so `phaseRemaining` is frozen (exactly the reported "same static time" in
  warm-up, work, and rest). Haptics (`haptics.tick`) never fire either.

The phone version does this correctly — `IntervalView.swift:190-208` calls
`advance()` (which sets `runner.now = Date()`) from its timeline-driven loop.

### Design
Mirror the phone's pattern, adapted for Always-On:

```swift
TimelineView(.periodic(from: .now, by: 0.5)) { context in
    content(date: context.date)              // reads the date → invalidates
        .onChange(of: context.date) { _, d in advance(to: d) }
}
```

`advance(to:)` sets `runner.now`, fires `haptics.tick(runner:)`, and handles
completion — one code path, testable ordering. In Always-On (`isLuminanceReduced`)
the cadence naturally drops to ~1 Hz; hide the flashing "imminent" animation there.

### Implementation steps
1. Restructure `WatchIntervalView` body as above; delete the dead outer `.onChange`.
2. Add `@Environment(\.isLuminanceReduced)`; suppress flash + sub-second styling.
3. Extend the watch smoke test: start Boxing, wait 2 s, assert the countdown label
   text **changed** (regression test for this exact bug; stays within the ≤3-test cap).

### Testing
- `IntervalRunner` math is already covered (17 headless tests) — untouched.
- The smoke assertion above is the view-wiring regression net.

---

## 2b. Workouts are never saved to HealthKit (latent, blocks watch-only)

### What the code does today
`stopWorkout()` (`WatchWorkoutManager.swift:104-116`) calls
`builder.endCollection(withEnd:)` and `session.end()` but **never calls
`builder.finishWorkout()`**. The half-finished builder is dropped. Consequences:

- No `HKWorkout` sample exists → **no Activity-ring credit** for any watch workout.
- The phone's HealthKit ingest (FR-3: "ingest Watch-recorded workouts + HR") has
  nothing to ingest → watch cardio would be invisible to history/coach.
- HR samples collected during the session are orphaned.

### Design
Proper teardown sequence, driven by the session-state delegate:

```
session.end()
  → didChangeTo .ended
    → builder.endCollection(withEnd:) { builder.finishWorkout { … } }
```

`stopWorkout()` becomes `stopWorkout(save: Bool)` — `save: false` calls
`builder.discardWorkout()` (used by the Live HR quick session and by Cancel paths).
Completion updates a `lastSavedWorkout` published summary (duration, avg HR,
kcal) that summary screens read.

### Implementation steps
1. Implement the state-driven teardown in the `HKWorkoutSessionDelegate` extension;
   make `stopWorkout(save:)` idempotent (double-tap End must not crash).
2. Interval + strength + cardio flows pass `save:` explicitly (Cancel → false).
3. Device verification: complete a 2-min Boxing session → workout appears in the
   watch Activity app and, minutes later, in the phone's HealthKit ingest.

### Data-model deltas
None. (Pure HealthKit lifecycle.)

### Open questions
None — this is mechanical correctness work.
