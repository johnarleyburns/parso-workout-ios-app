# FR-8 — Apple Watch live HR relay to iPhone

> Build the watchOS side so the Apple Watch optical sensor can stream live heart
> rate to the iPhone during any workout, feeding the same pipeline as the BLE
> chest strap.

## Problem
- The iPhone **cannot** read the Watch's live HR directly (HealthKit only gives
  periodic, stale samples).
- Live HR from the Watch requires a **watchOS `HKWorkoutSession`** — the session
  unlocks continuous sensor reading.
- The Watch must relay HR samples to the phone in near-real-time via
  **`WCSession`**.

## Current state of the Watch app
- **File:** `Cadence/Cadence Watch App Watch App/Cadence_Watch_AppApp.swift` (85 lines)
  — single `QuickLogView` (Bench Press, weight/reps steppers, "Log Set").
- **Zero** HealthKit code, zero entitlements, zero `WCSession`, zero `HKWorkoutSession`.
- **Entitlements** (`Cadence Watch App Watch App.entitlements`): only `aps-environment`
  + CloudKit — **no `com.apple.developer.healthkit`**.
- **Info.plist** (`Cadence-Watch-App-Watch-App-Info.plist`): only `UIBackgroundModes:
  remote-notification` — **no HealthKit usage strings**.

## Architecture

```
┌──────────────────────────────────┐
│  Watch                          │
│  WatchWorkoutManager            │
│   ├─ WCSession (delegate)       │  ← listens for "start_workout"
│   ├─ HKHealthStore              │
│   ├─ HKWorkoutSession           │  ← unlocks live HR
│   └─ HKLiveWorkoutBuilder       │  ← reads statistics (HR every 1s)
│       │                         │
│       ▼ stream ["bpm": 72]      │
└─────── WCSession ───────────────┘
         │
         ▼
┌──────────────────────────────────┐
│  iPhone                         │
│  AppModel (WCSessionDelegate)   │
│   ├─ sends "start_workout"      │
│   ├─ receives HR messages       │
│   └─ → HeartRateMonitor         │
│         .injectExternalBPM(_:)  │
│              │                  │
│              ▼                  │
│   CardioRecorder / IntervalView │ ← same pipeline as chest strap
│   SessionView (strength)        │
└──────────────────────────────────┘
```

## Implementation — Phase by phase

### Phase 1: Protocol + HeartRateMonitor (CadenceCore + phone)
**Add `injectExternalBPM` to the pipeline so the Watch can feed in.**

- `HeartRateMonitoring` protocol: add `func injectExternalBPM(_ bpm: Double)`
- `HeartRateMonitor`: implement it — sets `_bpm`, clears any active buffer,
  sets state to `.connected` (if not already), marks `battery = nil` (watch battery
  is separate).
- `FakeHealthProvider` (UI tests): no change needed (doesn't conform).

**Files:** `CadenceCore/Sources/CadenceCore/Services.swift`,
`Cadence/Cadence/Services/HeartRateMonitor.swift`

### Phase 2: Watch entitlements + Info.plist
**Give the watch app permission to read HR.**

- `Cadence Watch App Watch App.entitlements`: add
  ```xml
  <key>com.apple.developer.healthkit</key>
  <true/>
  ```
- `Cadence-Watch-App-Watch-App-Info.plist`: add
  ```xml
  <key>NSHealthShareUsageDescription</key>
  <string>Cadence reads heart rate from your Apple Watch during workouts.</string>
  <key>NSHealthUpdateUsageDescription</key>
  <string>Cadence saves your workout summary to Health.</string>
  <key>WKBackgroundModes</key>
  <array><string>workout-processing</string></array>
  ```
- Also add the standard `UIBackgroundModes` entry for workout processing.

### Phase 3: Watch `WatchWorkoutManager` (new file)
**The core watch component — starts HKWorkoutSession, reads HR, relays via WCSession.**

- Create `Cadence Watch App Watch App/WatchWorkoutManager.swift`
- Class: `WatchWorkoutManager` — `NSObject`, `@Observable`, conforms to
  `WCSessionDelegate`, `HKWorkoutSessionDelegate`, `HKLiveWorkoutBuilderDelegate`
- Stored state: `currentBPM: Double?`, `isActive: Bool`, `workoutType`
- Methods:
  - `startWorkout(type: CardioType)` — request HK auth, start `HKWorkoutSession`
    (map `CardioType` → `HKWorkoutActivityType`), begin `HKLiveWorkoutBuilder`,
    start periodic HR query
  - `stopWorkout()` — end session + builder
  - `activateWCSession()` — called on app init
- HR reading: use `HKLiveWorkoutBuilder` statistics — once the builder collects
  data, read heart rate from `builder.statistics(for: .heartRate)`. Alternatively,
  use `HKAnchoredObjectQuery` with `HKObjectType.quantityType(forIdentifier: .heartRate)`
  polling every 1s via `Timer`.
- WCSession receive: handle `"start_workout"` message from phone (dict with
  `"type": "boxing"`), `"stop_workout"`.
- WCSession send: every 1s, send `["bpm": bpm, "active": true]` via
  `sendMessage(_:replyHandler:errorHandler:)`.

### Phase 4: Watch app wiring
**Update watch app entry point to use WatchWorkoutManager.**

- `Cadence_Watch_AppApp.swift`: initialize `WatchWorkoutManager` as `@State`, inject
  via `.environment()`. Update `QuickLogView` or create a new `WatchHRView` that shows
  current BPM + "Start" / "Stop" buttons.
- For MVP: the watch UI can be minimal — just show HR and a Start/Stop toggle.

### Phase 5: Phone `AppModel` WCSession
**The phone receives HR and feeds it into the pipeline.**

- `Cadence/Cadence/App/AppModel.swift`:
  - Import `WatchConnectivity`
  - Conform to `WCSessionDelegate` (extend or inline)
  - On init: activate `WCSession.default`
  - Method: `startWatchWorkout(type: CardioType)` — sends `["command": "start_workout", "type": type.rawValue]` to watch
  - Receive: `session(_:didReceiveMessage:)` → parse `["bpm": Double]` → call
    `hrm.injectExternalBPM(bpm)`
- The phone-side WCSession activation should check `WCSession.isSupported()` and
  `WCSession.default.isWatchAppInstalled` before sending commands.

### Phase 6: Integration with workout start flow
**When a boxing/HIIT/strength workout starts, optionally fire up the Watch.**

- In `HomeView` or the interval/cardio/strength start path:
  - If no BLE chest strap is connected AND `WCSession.default.isWatchAppInstalled`:
    - Show option to "Use Watch HR" instead of / alongside "Connect Strap"
    - On selection, call `model.startWatchWorkout(type:)`
  - When workout ends, call `model.stopWatchWorkout()`
- Or simpler: auto-start Watch HR when a workout begins and no strap is connected.
  The pre-workout HR screen (`PreWorkoutHRView`) gets a third option: "Use Watch HR"
  alongside "Use this HR" (strap) and "Continue without HR".

### Phase 7: Cleanup on workout end
- Phone sends `"stop_workout"` to watch when workout finishes
- Watch ends the `HKWorkoutSession`, which auto-saves the workout to HealthKit
  (this gives the user a Watch-native workout entry too).

## Data model — no changes needed
- The existing `HRSamplePoint`, `CardioWorkoutSummary.hrSamples`,
  `StrengthWorkoutSummary.hrSamples` already handle the data.
- The phone-side HR pipeline (`CardioRecorder`, `IntervalView`, `SessionView`)
  reads `HeartRateMonitor.currentBPM` — it doesn't care whether the source is
  BLE or Watch.

## File manifest

| File | Action | Phase |
|------|--------|-------|
| `CadenceCore/Sources/CadenceCore/Services.swift` | Edit — add `injectExternalBPM` to protocol | 1 |
| `Cadence/Cadence/Services/HeartRateMonitor.swift` | Edit — implement `injectExternalBPM` | 1 |
| `Cadence Watch App Watch App/Cadence Watch App Watch App.entitlements` | Edit — add healthkit | 2 |
| `Cadence/Cadence-Watch-App-Watch-App-Info.plist` | Edit — add HK usage strings + background mode | 2 |
| `Cadence Watch App Watch App/WatchWorkoutManager.swift` | **New** — HKWorkoutSession + WCSession + HR relay | 3 |
| `Cadence Watch App Watch App/Cadence_Watch_AppApp.swift` | Edit — wire WatchWorkoutManager | 4 |
| `Cadence/Cadence/App/AppModel.swift` | Edit — WCSession delegate + HR relay | 5 |
| `Cadence/Cadence/Features/Shared/PreWorkoutHRView.swift` | Edit — optional: add "Use Watch HR" option | 6 |

## Testing considerations
- Requires **real Apple Watch hardware** — simulator cannot run HKWorkoutSession
  or WCSession.
- Unit tests can cover:
  - `injectExternalBPM` on `HeartRateMonitor` (set `_bpm`, clear buffer)
  - `CardioType` → `HKWorkoutActivityType` mapping
- UI tests: not feasible for watch + WCSession without hardware.
- Manual test: pair watch → start boxing on phone → verify Watch HR appears
  in live readout on phone.

## Decisions pending
1. **Watch workout type mapping**: Map `CardioType.boxing` → `.boxing`,
   `.hiit` → `.highIntensityIntervalTraining`, etc. For strength, use
   `.functionalStrengthTraining`.
2. **Auto-start vs manual**: Should the phone auto-trigger the Watch HR stream
   when a workout starts and no strap is connected? Or a manual button?
   **Recommendation**: auto-trigger for MVP — simpler UX, fewer taps.
3. **Watch saves its own HKWorkout?**: When the Watch's `HKWorkoutSession` ends,
   it auto-saves a workout to HealthKit. This is fine — it creates a Watch-native
   workout entry that our phone-side HealthKit ingest (FR-2.1) will pick up and
   deduplicate via `healthKitWorkoutUUID`.
