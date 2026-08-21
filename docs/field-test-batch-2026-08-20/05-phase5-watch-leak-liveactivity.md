# P5 — Watch workout leak + never-stopping "live activity" (field-test issue 5)

## Problem

> On the watch when I synced to my iPhone for live HR during cardio it worked
> great, BUT now I have this "live activity" for Cladiron with an active timer
> that keeps going on (gone on for hours now!) and it never stops, and I have no
> way to stop it even though the exercise ended hours ago. Furthermore it
> appears to block me from reading HR from the watch for future Cladiron cardio
> workouts, and when I try "Check for Live HR" it makes my iPhone heart rate
> screen unresponsive to any input.

## Root cause (two independent leaks)

### 5A — Cardio end/cancel never stops the watch's workout session

`model.stopWatchWorkout()` (sends `stop_workout` over WatchConnectivity) is
called from exactly **four** places:

| Call site | Path |
|---|---|
| `SessionView.swift:872` | strength `endWorkout` |
| `IntervalView.swift:231` | interval finish |
| `PreWorkoutHRView.swift:103` | Continue-without-HR |
| `PreWorkoutHRView.swift:152` | Connect-strap button |

None of the **cardio recorder** terminal paths call it:
- `RecordCardioView.endWorkout` (`RecordCardioView.swift:143-156`) + its Cancel (`:48`)
- `OutdoorCardioView.end` (`OutdoorCardioView.swift:159-175`) + its Cancel (`:110`)
- `SwimRecordView.endSwim` (`SwimRecordView.swift:119-135`)
- `HomeView.releaseCardioWorkout` (`HomeView.swift:902-905`) — the central
  onDismiss/onSaved hook for **all** cardio surfaces (`:325-430`)

Consequence chain (matches the report exactly):

1. User starts cardio from the HR gate with Apple Watch HR → `PreWorkoutHRView.swift:70`
   → `model.startWatchWorkout` → the watch starts an `HKWorkoutSession` **and a
   `WKExtendedRuntimeSession`** and stores `phoneRequestID`
   (`WatchWorkoutManagerSync.swift:68-69`).
2. User ends the cardio on the phone → recorder saves, but **no `stop_workout`**
   is sent → the watch session + extended runtime session keep running for
   **hours** (the "live activity / active timer that never stops" the user sees
   on the watch — the watch's workout UI/dock indicator; `WKExtendedRuntimeSession`
   is designed for long stretches). `relayBPM` keeps streaming
   (`WatchWorkoutManager.swift:299-303`).
3. Next cardio's `Check for Live HR` → `start_workout` → the watch rejects with
   `.alreadyActive` (`WatchWorkoutManagerSync.swift:65-67`) → the phone's relay
   can never reach `.live` for the new requestID → the 15 s timeout
   (`AppModel.swift:209-212`) fires `.timedOut` — **blocking future watch HR**.
4. The HR screen appears unresponsive because the relay is stuck and (per P6) the
   Continue button is disabled.

### 5B — Phone Live Activity can be orphaned

`WorkoutLiveActivityCoordinator` (`Cadence/Cadence/LiveActivity/WorkoutLiveActivity.swift:24-53`)
holds one `activity` reference; `end()` is called only from
`RootTabView.swift:131-137` when `active.isActive` flips. If the app is killed
or backgrounded while a workout is active, the singleton drops the reference and
**no code ever enumerates `Activity.activities` to clean up stale ones** on
relaunch. (Today there is no widget extension target — `plans/iphone-field-testing/2026-08-13/01-widget-extension-target.md`
— so this specific ActivityKit surface isn't rendering on the lock screen, but
the orphan is exactly the risk that plan's §4 flagged, and fixing it here closes
the "never stops" family even when the widget lands.)

## Design

### 5A-1. Every cardio terminal path stops the watch session

Add `model.stopWatchWorkout()` (already a safe no-op when no watch session /
`wcSession` is nil — `AppModel.swift:255-265`) to:
- `RecordCardioView.endWorkout` and its Cancel action.
- `OutdoorCardioView.end` and its Cancel action.
- `SwimRecordView.endSwim`.
- `HomeView.releaseCardioWorkout` (`HomeView.swift:902-905`) — the catch-all for
  every cardio surface's onDismiss/onSaved, so a future cardio screen can't
  regress this again. Guard stays as-is (`active.strengthSession == nil`).

`stopWatchWorkout` already stops the relay (`watchHRRelay.cancel()`), so the HR
gate state resets cleanly for the next workout.

### 5A-2. `.alreadyActive` recovery — stop, then retry once

When `start_workout` is rejected with `.alreadyActive`, the phone should
recover, not give up:

- `WatchHRRelay` (CadenceFeatures, `WatchHRRelay.swift:24-67`) gains a state or a
  decision helper: `func shouldRetryAfterStop(rejection:) -> Bool` — `true` for
  `.alreadyActive` (a stale session is exactly the failure this phase fixes),
  `false` for the other rejections (don't hammer a permission failure).
- `AppModel.startWatchWorkout(rawType:)` — on the rejection reply with
  `.alreadyActive` (via `watchReplyHandler` at `AppModel.swift:215-229`):
  1. `stopWatchWorkout()` (sends `stop_workout`, clears the relay).
  2. After a short beat (e.g. 1.0–1.5 s for the watch to tear down), call
     `startWatchWorkout(rawType:)` **once** (new requestID).
  3. If the retry is rejected again, surface the existing
     `watchHRRelay.fail("…already active…")` message so the user sees a real
     error instead of a silent hang.
- One retry only — no loops. The retry is gated so it never fires when the user
  is not on the HR screen.

This lives partly in AppModel (app target) and partly in a pure
CadenceFeatures helper; the decision "reject → stop → retry" is the testable
core.

### 5A-3. Ignore stale BPM (already largely true — make it explicit)

`AppModel.handleWatchMessage` (`AppModel.swift:310-336`) already gates injection
on `watchHRRelay.receive(...)` returning true, which requires the **current**
requestID. No change needed; the 5A-1/5A-2 fixes eliminate the root. (Recorded
here so nobody "fixes" this by loosening the guard.)

### 5B-1. Live Activity stale cleanup on launch

`WorkoutLiveActivityCoordinator` gains:

```swift
@MainActor
func endAllStale() {
    for activity in Activity<WorkoutLiveActivityAttributes>.activities {
        Task { @MainActor in await activity.end(nil, dismissalPolicy: .immediate) }
    }
    activity = nil
}
```

Call `endAllStale()`:
- On app launch — `CadenceApp.swift` `.task` (alongside `activateWCSession`).
- At the top of `start(title:)` — always end any prior before requesting a new
  one, so a stale activity can never be left behind by an interrupted transition.

`Activity.activities` returns only this app's type; harmless when empty.

### 5A-4. (Defense-in-depth, watch side) — optional, gated on decision D7

The watch could auto-tear-down a session that has been unreachable from the
phone for a long stretch. **Risk:** a legitimately-minimized workout with the
phone in the pocket would be killed. Recommend **not** shipping this in the
batch; the phone-driven stop is the primary fix. Revisit only if hardware
testing still leaks.

## Data-model deltas

None. `WatchHRRelay` adds a pure decision function; `AppModel` gains a small
retry state (transient, not persisted).

## Implementation steps

1. `WatchHRRelay.shouldRetryAfterStop(rejection:)` + tests.
2. `AppModel.startWatchWorkout(rawType:)` — `.alreadyActive` → stop → retry once.
3. `RecordCardioView`, `OutdoorCardioView`, `SwimRecordView`, `HomeView.releaseCardioWorkout`:
   add `model.stopWatchWorkout()`.
4. `WorkoutLiveActivityCoordinator.endAllStale()` + launch/`start` wiring in
   `CadenceApp.swift` and `WorkoutLiveActivity.swift`.
5. `swift test` + `make pre-commit`.

## Testing

### Unit tests (CadenceFeaturesTests)

- `WatchHRRelayTests` (new file):
  - `testAlreadyActiveShouldRetryAfterStop` — `.alreadyActive` → `true`.
  - `testPermissionDeniedShouldNotRetry` — `.healthPermissionDenied`/
    `.unsupported`/`.unavailable` → `false`.
  - `testRelayRecoverySequence` — begin(newID) → fail("already active") →
    begin(retryID) → acknowledged → receive → `.live`.
- The "every cardio end calls stopWatchWorkout" property is app-target wiring;
  it cannot be headless-tested. It is covered by the smoke addition below and
  the audit table in this file.

### iPhone smoke test — one seam, one assertion

Add a UI-test seam: a launch argument (`-uiTestWatchStop`) that makes
`AppModel.stopWatchWorkout` record into `@AppStorage("uitest.watchStopCount")`
(a counter) instead of (or in addition to) sending the message. Then, in the
existing flow, end a cardio workout — the smoke flow currently runs only a
strength workout, so add the cheapest real cardio end:

1. From Home tap `home.startWorkout` (already there), cancel, then start a
   **timer cardio** (`selectWorkout` → cardio grid → `startType.run`) → HR gate →
   `prehr.start` (Continue without HR) → live screen → `record.end` → confirm.
2. Assert `uitest.watchStopCount` increased.
3. Also assert the HR-gate screen is responsive: `prehr.start` is enabled
   (see P6).

This is the one smoke-growth the user's report justifies: the leak was reported
from real hardware and this assertion proves the end-path contract on every
commit. Estimated +~15–20 s. If runtime is a concern, the seam + a
strength-end assertion (already exercised) can substitute, but the cardio end is
the actual regression.

### Watch UI smoke — unchanged (still exactly one watch test).

### Honest gap — hardware

The evidence for "the timer stops / future HR reads work" rests on the stop-path
wiring, the retry test, and the smoke seam — **not** on a real device. The user
should re-check on the next device run (same honesty note as the `7a5d6c7`
watch fix): end a cardio workout that used watch HR, confirm the watch's
workout indicator disappears, then start another and confirm `Check for Live HR`
goes live.

## Open questions

- D7: watch-side auto-tear-down (recommend: not in this batch).
- Whether the stale phone Live Activity cleanup should also trigger on
  `scenePhase → .background` of a *non-active* workout (recommend: launch +
  `start` are enough).
