# iPhone field-testing fixes — 2026-08-13

## Scope

Fix the seven issues reported during iPhone field testing while preserving the
existing iPhone/watch workout model and the Swift 6/test-pyramid rules. The
watch companion is included where it consumes the same behavior or sync data.

## What the code does today

1. `Exercise` rows are SwiftData entities, but the watch creates its own local
   non-CloudKit container (`Cadence_Watch_AppApp.swift`). Phone-created custom
   exercises therefore cannot arrive in the watch catalog. `WatchSync` only
   transfers preferences and today's plan; the watch search indexes its local
   `@Query` rows.
2. `GuidedPhaseOverlay` uses a wall-clock countdown, but its display refresh is
   the only lifecycle mechanism. The warm-up is owned by `HomeView` and has no
   explicit scene-lock policy, so lifecycle transitions need to be made
   unambiguously non-pausing.
3. There is no ActivityKit target or workout Live Activity. The watch uses
   `HKWorkoutSession`, which already provides its own active-workout system UI;
   the iPhone needs a Live Activity backed by the active workout state.
4. `WallClockLabel` refreshes through a 30-second Combine timer and is reused by
   strength, interval, outdoor, swim, and timer-cardio screens. Replace this
   with a lifecycle-safe current-time view so it cannot remain stale during a
   workout.
5. Set columns are hard-coded in `SessionViewShared.swift`; partner WHO is
   wider than needed, and completed rows render RPE but only the editor's
   context menu can set it. RIR is not represented in the iPhone editor. The
   editor must expose effort mode/value directly and completed rows must offer a
   discoverable edit action.
6. Strength completed rows use `decimals: 0`, truncating the display precision
   users entered. Input canonicalization remains unchanged; display should use
   quarter-unit precision.
7. Strength auto-starts watch HR in `SessionView`, while interval/HIIT startup
   routes through the chest-strap HR gate and never offers the watch. Other
   cardio follows the same gap when watch HR is selected.

## Design

- Add a shared, deterministic exercise-catalog payload to `WatchSync` and send
  it with the application context; the watch applies it to its local SwiftData
  store, preserving stable IDs and all search facets. Add a message fallback
  when the watch is reachable so a newly-created exercise appears without
  waiting for a context refresh. Watch-created exercises continue to sync to
  the phone through the existing workout relay/CloudKit path.
- Make guided phases explicitly continue across `.inactive`/`.background` and
  document/test that only the Pause button changes countdown state.
- Add a small `ActivityKit`-backed iPhone Live Activity coordinator and widget
  extension target. Start/update/end it from the active strength and cardio /
  interval lifecycle. The Live Activity shows workout kind, phase/status, and
  elapsed time; it is best-effort when ActivityKit is unavailable or denied.
  The watch remains on `HKWorkoutSession` and does not get a duplicate
  ActivityKit surface.
- Use a `TimelineView`-driven wall clock and inject/centralize the formatter so
  all existing workout headers update while active.
- Introduce effort editing as a visible RPE/RIR segmented control plus value
  picker in `InlineSetEditorView`; persist the canonical RPE and derive RIR as
  `10 - RPE`. Add accessibility identifiers and an edit button for completed
  RPE/RIR cells. Tighten columns: WHO 20, centered weight/reps/LB labels, and
  enough RPE width for the value.
- Render set weight at quarter-unit precision in the strength table while
  retaining exact stored kg and the existing optional plate-rounding setting.
- Centralize “offer Apple Watch or Bluetooth” in the pre-workout HR gate and
  call it for interval/HIIT and watch-capable cardio. Selecting Watch starts the
  corresponding watch workout; selecting Bluetooth preserves the existing BLE
  flow.

## Implementation steps

1. Add pure sync/effort/precision policies in `CadenceFeatures` and unit tests.
2. Wire phone/watch custom-exercise catalog transfer and search refresh.
3. Fix phase lifecycle and wall-clock rendering.
4. Add iPhone ActivityKit Live Activity target, coordinator, and lifecycle
   wiring; verify the watch path remains native `HKWorkoutSession`.
5. Fix set layout and visible RPE/RIR editing.
6. Fix HR-source choice for interval and cardio launches.
7. Add/extend iPhone UI smoke coverage for custom exercise search, visible
   effort editing, and active workout status; keep the UI suite under the
   repository's 12-test cap. Add unit tests for all deterministic policies and
   lifecycle transitions.

## Acceptance tests

- A custom exercise created on iPhone is searchable and selectable on Watch
  after sync; a custom created on Watch remains usable on iPhone.
- Locking the phone during warm-up does not pause or reset the phase; the timer
  reflects elapsed wall time on return. Only Pause pauses it.
- An active iPhone strength/cardio/HIIT workout produces a lock-screen Live
  Activity and removes it on finish/cancel. Watch workouts continue to use the
  native watch workout surface.
- The wall clock changes with the current time in all workout surfaces.
- Set headers/cells are centered and fit on iPhone; WHO is narrow; RPE and RIR
  can be entered, changed, cleared, and are accessible.
- `20.25 kg` / its quarter-unit equivalent displays without integer rounding.
- HIIT and other watch-capable cardio offer Apple Watch as an HR source in
  addition to Bluetooth.

## Verification and delivery

- `swift test` in `CadenceCore`.
- iPhone UI smoke test on the iPhone simulator, plus a watch build/test if the
  new sync code touches the watch target.
- Re-read this plan against the implementation and update `current_state.md`.
- Commit on this branch, fast-forward merge into `main`, push `origin/main`,
  and inspect the latest GitHub Actions run with `gh`.

## Open/intentional decisions

- ActivityKit is iPhone-only: Apple Watch's workout session already owns the
  system workout presentation and the user report is specifically about the
  iPhone lock screen.
- Review deviation: this repository currently has no widget-extension target;
  the implementation adds the ActivityKit state coordinator and entitlement,
  but the lock-screen renderer still requires follow-up Xcode target wiring
  before this acceptance item can be called complete.
- Existing persisted model fields remain additive; no destructive SwiftData
  migration is introduced.
