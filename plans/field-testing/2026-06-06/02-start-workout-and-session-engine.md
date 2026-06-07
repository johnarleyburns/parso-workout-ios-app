# §02 — Start Workout & Session Engine

> Addresses field note **#3 (Start Workout → quick type picker → a custom screen
> per type)** and the lifecycle parts of **#4 (easy begin/end, 10-min idle
> auto-terminate, continue across interruptions / backgrounding)**. This section
> defines the **type picker** and the **shared session engine** every workout
> screen (strength §04, cardio §05, intervals §06) sits on top of.

Decisions applied: #6 (prompt + auto-save), #7 (10-min adjustable, paused during
active timers), #8 (one active session), #9 (type list).

---

## Problem (from the field test)

- "When clicking Start Workout you should quickly be able to select the type —
  weight training, running, boxing, etc — and then **each training type has its
  own custom screen**." Today there is no unified Start: strength lives in
  `TrainView` (New Workout button), cardio in `CardioView` (Record Workout →
  `RecordCardioView`'s own grid). Two separate entry points, inconsistent.
- "Let me **begin/end a workout easily**", "**auto-terminate after 10 min of no
  entry** so they don't accidentally last forever", and "**continue workouts if I
  need to take a phone call — make sure backgrounding works**."

## What the code does today

- `RecordCardioView.swift` already has a type grid (`run, cycle, walk, boxing,
  hiit, rowing`) and a 1 Hz `Timer.publish` driving `CardioRecorder.tick()`.
  `CardioRecorder` (`Features/Cardio/CardioRecorder.swift`) is an `@Observable`
  with `start/pause/resume/end`, elapsed seconds, HR samples, and metrics.
- Strength has **no recorder/lifecycle** — `SessionView` just edits a
  `WorkoutSession` directly; there's no notion of "active", no idle timeout, no
  background handling. `saveToHealth()` is manual via a toolbar button.
- There is **no single Start Workout entry**, no auto-terminate, and the 1 Hz
  timer in `RecordCardioView` **stops when backgrounded** (a SwiftUI `Timer`
  publisher doesn't run in the background) — so the "phone call" requirement is
  currently unmet for cardio and absent for strength.

## Research signal

- Best-in-class apps treat "start" as one decision: a fast type chooser, then a
  purpose-built screen. (Hevy/Strong/Fitbod; fitness-UX "one decision per
  screen".)
- iOS reality for "survives a phone call / pocket": foreground `Timer`s pause in
  background. Continuous timing must be **wall-clock based** (compute elapsed
  from `startDate`, not by counting ticks) and long-running work needs an
  appropriate background mode (location for GPS cardio; otherwise the workout
  keeps *logical* time and simply recomputes on return to foreground).

Sources:
- https://stormotion.io/blog/fitness-app-ux/
- https://www.findyouredge.app/news/best-strength-training-apps-2026

---

## Design

### A. The Start Workout flow

From Home (§01) `home.startWorkout` → **`WorkoutTypePicker`** (a sheet or pushed
screen). Big, legible, icon+label cards (low-vision friendly; ≥44pt, large type):

```
┌──────────────────────────────┐
│  Start Workout            ✕  │
│                              │
│  ┌─────────┐  ┌─────────┐    │
│  │ 🏋️       │  │ 🏃       │    │
│  │ Weights │  │  Run    │    │   GPS badge on Run/Walk/Cycle
│  └─────────┘  └─────────┘    │
│  ┌─────────┐  ┌─────────┐    │
│  │ 🚶 Walk  │  │ 🚴 Cycle │    │
│  └─────────┘  └─────────┘    │
│  ┌─────────┐  ┌─────────┐    │
│  │ ⚡ HIIT  │  │ 🥊 Boxing│    │
│  └─────────┘  └─────────┘    │
│  ┌─────────┐                 │
│  │ … Other │                 │
│  └─────────┘                 │
└──────────────────────────────┘
```

- Order (decision #9): **Weights, Run, Walk, Cycle, HIIT, Boxing, Other.**
- Each card routes to its purpose-built screen:
  - Weights → **`StrengthSessionView`** (§04, evolves today's `SessionView`).
  - Run / Walk / Cycle → **`OutdoorCardioView`** (§05, GPS + map).
  - HIIT → **`IntervalView`** in HIIT mode (§06).
  - Boxing → **`IntervalView`** in boxing mode (§06).
  - Other → generic timer cardio (today's `RecordCardioView` live screen).
- **Routing is a thin map** from the chosen type to a screen + a freshly created
  session via the engine below. No giant switch in the view — a
  `WorkoutType` enum with an associated launch.

> Note: this **replaces** `CardioView`'s "Record Workout" entry and
> `TrainView`'s "New Workout" button as the single front door. The two old
> screens' *history* lists move to History/Stats (§01); their *start* buttons
> retire.

### B. The session engine (shared, in `CadenceCore`)

A single lifecycle abstraction reused by strength, cardio, and intervals so the
begin/end/idle/background rules are written **once** (CLAUDE.md: logging logic
lives in core, headlessly testable).

New core type — **`WorkoutClock`** (pure, testable, no UIKit):

```
public struct WorkoutClock {
    public var startedAt: Date
    public var endedAt: Date?
    /// Accumulated paused time, so elapsed excludes pauses.
    public var pausedAccumulated: TimeInterval
    public var pausedSince: Date?

    /// Wall-clock elapsed, correct after backgrounding (no tick counting).
    public func elapsed(now: Date = .now) -> TimeInterval { ... }
}
```

New core type — **`IdleWatchdog`** (pure):

```
public struct IdleWatchdog {
    public var timeout: TimeInterval          // decision #7: default 600s
    public var lastActivityAt: Date
    public var isArmed: Bool                   // false while a timer/round runs
    /// Seconds until auto-terminate, or nil if disarmed/never.
    public func remaining(now: Date) -> TimeInterval?
    public func hasExpired(now: Date) -> Bool
}
```

Rules:
- **Wall-clock elapsed.** Every screen computes elapsed from `WorkoutClock`, not
  by summing 1 Hz ticks → correct after a phone call / background. The 1 Hz
  timer becomes a *display refresh only*; the truth is `Date`.
- **Idle watchdog** (decision #6/#7): "activity" = a logged set (strength),
  movement/HR sample (cardio), or any user interaction. After `timeout` (default
  **600 s**, Settings-adjustable) of no activity, show a **"Still training?"**
  sheet with a visible countdown (e.g. 30 s). If the user taps "Keep going" →
  re-arm. If they don't respond → **auto-save & finalize** (never silent
  discard). The watchdog is **disarmed while an interval/round timer is actively
  running** (decision #7) — a 4-minute Norwegian block isn't "idle."
- **One active session** (decision #8): the engine holds a single
  `activeSession` reference (surfaced to Home's Resume card, §01). Tapping Start
  while one is live → "Resume <type> · 00:34" vs "Start new (saves current)".
- **Backgrounding / interruptions:**
  - Strength & interval & indoor cardio: no special background mode needed —
    elapsed is wall-clock; on `scenePhase` return to `.active`, recompute and
    re-render; the OS suspends the app but the session state is intact (it's in
    SwiftData / the engine).
  - GPS cardio (§05): uses the **location background mode** so route capture
    continues during a call / pocket (LocationTracker already exists; §05 wires
    the background mode + `pausesLocationUpdatesAutomatically`).
  - Persist `activeSession` id + `startedAt` to `UserDefaults`/SwiftData on
    `scenePhase` change so a **cold kill** mid-workout can offer "Resume your
    workout?" on next launch (NFR-5 reliability/offline).
- **Easy begin/end:** Start = one tap from the type card (creates the session +
  routes). End = a prominent button on each screen → confirm → finalize (writes
  summary `HKWorkout` where applicable, stamps `end`, clears `activeSession`).

### C. Where the engine lives

- `CadenceCore`: `WorkoutClock`, `IdleWatchdog`, and a `WorkoutType` enum
  (the picker's source of truth, mapping to existing `CardioType` /
  strength) — all pure & unit-tested with injected `now`.
- App layer: a small `@Observable ActiveWorkoutModel` (in `App/`) owns the live
  session, drives the 1 Hz display tick, listens to `scenePhase`, presents the
  idle sheet, and exposes `activeSession` to Home. The per-type recorders
  (`CardioRecorder`, a new strength logger wrapper, interval engine §06) plug
  into it.

---

## Data-model deltas

Minimal — the engine is mostly behavior, not storage:
- `WorkoutSession` already has `date`; **add `endedAt: Date?`** (optional,
  CloudKit-safe) so strength sessions record a real end like cardio does. Used by
  duration and the idle finalizer.
- No new entities. `CardioWorkout` already has `start`/`end`.
- (All deltas consolidated in §07.)

## Mockup — idle prompt

```
┌──────────────────────────────┐
│        Still training?        │
│                              │
│   No activity for 10 min.    │
│   Saving this workout in     │
│            00:27             │   ← live countdown
│                              │
│  [ Keep going ]  [ Save now ]│
└──────────────────────────────┘
```

## Implementation steps

1. **Core:** add `WorkoutClock`, `IdleWatchdog`, `WorkoutType` to `CadenceCore`
   with `now`-injectable APIs; unit tests for elapsed-after-pause, idle expiry,
   disarm-while-running.
2. **`ActiveWorkoutModel`** (`App/`): owns active session, 1 Hz display tick,
   `scenePhase` observer, cold-launch resume, idle sheet presentation.
3. **`WorkoutTypePicker`** view + `home.startWorkout` wiring (§01); route each
   type to its screen with a fresh session.
4. **Add `endedAt`** to `WorkoutSession`; set it on finalize; update duration
   helpers.
5. **Retire** the old start entry points in `TrainView`/`CardioView` (their lists
   move per §01).
6. **Background:** set `scenePhase` recompute everywhere; defer GPS background
   mode to §05.

## Testing

- **Unit (swift test):** `WorkoutClock.elapsed` correct across pause/resume and a
  simulated 5-min background gap; `IdleWatchdog` expires at timeout, not while
  armed-off; cold-resume restores `startedAt`.
- **UI (iPhone + iPad):** Home → Start Workout → each type opens its screen;
  start a session, background the app (`XCUIDevice` deactivate/activate) →
  elapsed advanced by real time; idle prompt appears in a test build with a short
  injected timeout and "Save now" finalizes; Resume card reflects active session.
- **Accessibility:** type cards have VoiceOver labels; idle prompt is announced;
  countdown respects Reduce Motion.

## Open questions (resolved here; noted for visibility)

- Auto-terminate → prompt + auto-save (decision #6). ✔
- Timeout 10 min, adjustable, paused during active timers (decision #7). ✔
- One active session (decision #8). ✔
