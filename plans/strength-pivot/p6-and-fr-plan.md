# P6 + FR-2.3/4.4, FR-2.5, FR-8 — Combined Plan

> Written 2026-06-16. Covers the remaining roadmap before P7 (Reposition/App Store).

---

## P6: Cardio/anaerobic assessments + HIIT loop

### Research signal
- **VO₂max field tests** (Cooper 12-min run, Rockport walk) are well-validated
  proxies for aerobic capacity. Self-entered estimated VO₂max (mL/kg/min) is the
  unit coaches track longitudinally.
- **Wingate anaerobic test** (30s all-out on a cycle ergometer) is the gold-
  standard measure of anaerobic peak power and capacity. Recorded in absolute
  watts.
- **HIIT improves VO₂max:** Norwegian 4×4 and Tabata protocols both produce
  robust VO₂max gains. The "loop" is: assess → prescribe interval protocol →
  re-assess after a block.

### Design

#### P6.1 — AssessmentKind additions (Assessment.swift)

Two new enum cases:

| Kind | Unit | Category | Display | Symbol | ConcernsLift |
|------|------|----------|---------|--------|--------------|
| `vo2maxField` | `mlKgMin` (mL/kg/min) | `.cardio` | "VO₂max test" | `heart.text.clipboard` | false |
| `wingate` | `watts` (W) | `.cardio` | "Wingate test" | `bolt.fill` | false |

New `AssessmentCategory.cardio` ("Cardio").

New `AssessmentUnit` values: `.mlKgMin`, `.watts`.

#### P6.2 — Insight/Recommendation rules

**P6 insight rules** (read-only, join `p3Rules` + `p4Rules`):
- `cardioAssessmentProgress` — same pattern as `assessmentProgress` but for
  cardio kinds (cites Cooper 1968 / Wingate reference)
- `cardioAssessmentRetest` — same pattern as `assessmentRetest` for cardio

**P6 recommendation rules** (prescriptive, join `p5Rules`):
- `cardioHIIR` (VO₂max declining → Norwegian 4×4 or Tabata)
- `cardioSIT` (Wingate declining → SIT/Wingate intervals)
- Logic: declining cardio assessment trend → recommend the appropriate interval
  protocol. Improving → recommend continuing.

The `Recommendation` gains a new field for cardio prescriptions:
- `cardioTarget: CardioTarget?` — protocol name + parameters ("Norwegian 4×4",
  "4 rounds, 4 min work / 3 min rest")
- The "Do this workout" button routes to the interval picker with the
  recommended protocol pre-selected.

#### P6.3 — UI changes

- `RecordAssessmentView`: VO₂max → numeric text field ("mL/kg/min"). Wingate →
  numeric text field ("Watts").
- `AssessmentDisplay`: format mL/kg/min (one decimal), watts (integer).
- `PlanView`: cardio battery rows appear in a new "Cardio" section.

#### P6.4 — Citations

- **Cooper 1968**: "A means of assessing maximal oxygen intake" (JAMA 203(3))
- **Wingate reference**: Bar-Or 1987, "The Wingate Anaerobic Test"

---

## FR-2.3/4.4: BLE Chest Strap (Heart Rate Monitor)

### Current state
`HeartRateMonitor.swift` already implements CoreBluetooth scanning, connection,
and BPM subscription (0x180D / 0x2A37). The `HeartRateMonitoring` protocol is
defined in `CadenceCore/Sources/CadenceCore/Services.swift`. `CardioRecorder`
reads `hrm.currentBPM` during live cardio.

### What's missing
1. **Pairing UI** (UC-5): "Settings → Heart-Rate Monitor → Add Device" screen
   that scans for BLE peripherals advertising 0x180D, shows discovered devices,
   lets user tap to connect and save as default.
2. **Battery level** reading (characteristic 0x2A19 in Battery Service 0x180F).
3. **Auto-reconnect** on app launch to the saved default device.
4. **Persistence** of the remembered device UUID (UserDefaults).
5. **HealthKit save** of HR samples from strap-recorded sessions (overlaps with
   FR-2.5).

### Implementation plan
- Add `HRMPairingView` (scan → tap device → connect → save default)
- Add `BatteryService` read alongside existing HeartRateService
- Persist `defaultHRMId: UUID?` in `AppSettings`
- Auto-connect on `CardioRecorder.start()` or on `IntervalView` entry
- Reconnect logic with exponential backoff on signal drop

### Dependencies
- CoreBluetooth (already in use)
- HealthKit write (FR-2.5)

---

## FR-2.5: HealthKit Workout Writeback

### Current state
`HealthKitProvider.swift` exists but the complete writeback pipeline is not
fully integrated. `CardioWorkoutSummary` is produced by `CardioRecorder.end()`
and `CardioWorkout` is the SwiftData model — but the HealthKit `HKWorkout`
+ `HKQuantitySample` (HR, distance, energy) save path may not be complete.

### What's needed
For every completed workout (strength, cardio, intervals):
1. Write an `HKWorkout` with correct `activityType`, start/end, duration
2. Write `HKQuantitySample`s for heart rate (if captured)
3. Write `HKWorkoutRoute` for GPS-tracked outdoor workouts
4. Write `activeEnergyBurned` estimate
5. Handle permission priming before first save (FR-4.1)
6. Handle write failures gracefully (HealthKit is best-effort)

### Mapping activity types
| Our type | HKWorkoutActivityType |
|----------|----------------------|
| Strength | `.traditionalStrengthTraining` |
| Run | `.running` |
| Walk | `.walking` |
| Cycle | `.cycling` |
| Swim | `.swimming` |
| HIIT | `.highIntensityIntervalTraining` |
| Boxing | `.boxing` |
| Other | `.other` |

### Implementation
- `HealthKitWorkoutWriter` class (new) that takes a `CardioWorkoutSummary` (or
  strength summary) and writes the full sample batch to HealthKit
- Call from workout-completion paths (`CardioRecorder.end()`, session end, etc.)
- One-time permission priming: "Save to Health → close your rings → appear in
  Fitness app"

---

## FR-8: Watch HR Relay

### Research findings

#### The only Apple-supported architecture
```
Watch: HKWorkoutSession + HKLiveWorkoutBuilder → WCSession.sendMessage → Phone
```

| Approach | Viable? |
|----------|---------|
| Phone polls HealthKit for live HR | No — batches minutes behind |
| Phone starts HKWorkoutSession for Watch HR | No — phone can't read watch sensor |
| Phone reads Watch HR via BLE directly | No — Watch HR sensor is private |
| Watch relays HR via WCSession | **Yes** — sub-second latency |

#### Architecture
1. **Watch app** starts `HKWorkoutSession` (triggers high-freq HR sampling, ~1
   sample/sec)
2. `HKLiveWorkoutBuilder` collects live statistics (HR, energy, etc.)
3. `WCSession.sendMessage` relays latest BPM + timestamp to phone
4. **Phone app** `WCSession` delegate receives messages, updates a shared
   `LiveHRProvider` (unifying BLE strap + Watch sources)

#### Key constraints
- Watch HR is optical — 2-5s physiological lag, less accurate than chest strap
- `HKWorkoutSession` roughly doubles Watch battery drain (~5-8%/hour)
- `WCSession.sendMessage` adds ~5-50ms; total end-to-end ~2-7s
- Watch app must be foreground OR have running `HKWorkoutSession` (background)
- Phone app should be foreground for continuous display

### Current state
Watch app (`CadenceWatchApp.swift`) is a simple strength-logging stub with no
HealthKit, no `HKWorkoutSession`, no `WCSession`.

### Implementation plan
1. **CadenceCore:** Add `WatchHeartRateRelay` protocol / `LiveHRProvider` that
   unifies HR from BLE strap and Watch relay under one `currentBPM` source
2. **Watch app:** Add `WorkoutSessionManager` (HKWorkoutSession +
   HKLiveWorkoutBuilder) + `WCSession` relay to phone
3. **Phone app:** Add `WCSession` delegate that receives Watch HR and exposes
   it via the shared `LiveHRProvider`
4. **Integration:** Existing views (`IntervalView`, `CardioRecorder`,
   `RecordCardioView`) already read `hrm.currentBPM` — update to read from
   unified `LiveHRProvider` that aggregates strap + Watch sources

### Dependencies
- watchOS 10+ (already targeted)
- WCSession (both targets)
- HealthKit (both targets)

### Priority
FR-8 is needed before the app can show live HR when the user has a Watch but no
chest strap. Given the CLAUDE.md note that v1 is "iPhone-only" with Watch
"deferred," this is a v1.x enhancement. The chest strap path (FR-2.3/4.4) works
independently and ships first.

---

## Rollout order (one PR each)

| Phase | Branch | Content | Deps |
|-------|--------|---------|------|
| P6 | `p6/cardio-assessments` | AssessmentKind + rules + citations + UI | P4, P5 |
| FR-2.5 | `feat/hk-writeback` | HealthKit workout writer | P6 |
| FR-2.3/4.4 | `feat/ble-strap` | BLE pairing UI + battery + reconnect | FR-2.5 |
| FR-8 | `feat/watch-hr` | Watch HR relay | FR-2.3/4.4 |
| P7 | `p7/reposition` | Onboarding, goals, App Store | All above |
