# Cadence — Implementation Plan Status

Automated build of FR-1…FR-6 from `REQUIREMENTS.md`. Per-bullet plans live in
`plans/frX.Y/PLAN.md`. Each bullet is designed → implemented → tested (unit +
integration + **iPhone & iPad UI tests**) → reviewed against its plan.

## Process note
Per-bullet **plan documents** are written before implementation. Implementation
and commits are grouped per **FR** (the bullets within an FR share models and
screens, so shipping them together keeps every commit building and green).
Each FR is pushed on its own `feat/fr-N-*` branch.

## Test surfaces
- **CadenceCore** (`cd CadenceCore && swift test`): pure logic + SwiftData repo.
- **CadenceTests** (Swift Testing, app target): view-model/parsing logic.
- **CadenceUITests** (XCUITest): real flows, run on **iPhone 17** and
  **iPad Pro 11-inch (M5)**, launched in `-uiTest` mode (in-memory store +
  deterministic fake Health/BLE/GPS).

Run UI tests with `-parallel-testing-enabled NO` (simulator cloning is unstable
on this host).

---

## FR-1 Strength logging — ✅ COMPLETE
Branch `feat/fr1-strength`. Core 48 tests ✓ · app unit 9 ✓ · UI 7×2 (iPhone+iPad) ✓

| Bullet | Status | Notes |
|---|---|---|
| FR-1.1 create session + searchable library (custom + categories) | ✅ | `TrainView`, `ExercisePickerView`, `ExerciseLibrary` (25 starter lifts) |
| FR-1.2 multiple sets (weight/reps/RPE/note), mixed within exercise | ✅ | `SetEditorView`, `WorkoutRepository.addSet` |
| FR-1.3 inline last-time + current PR | ✅ | `lastTimeSets`, `currentPR` shown in card + editor |
| FR-1.4 auto-detect PR (configurable rule) | ✅ | `PRCalculator`, PR badge + haptic; rule/formula in Settings |
| FR-1.5 rest timer, auto-start on completion | ✅ | `RestTimerModel` (unit-tested) + `RestTimerBar` |
| FR-1.6 reusable templates | ✅ | `TemplatesView`, `TemplateEditorView`, `startSession(from:)` |
| FR-1.7 edit/delete sets & sessions | ✅ | editor edit/delete, swipe-delete, confirm dialog |

## FR-2 Cardio tracking — ✅ COMPLETE
Branch `feat/fr2-cardio`. Core 55 tests ✓ · UI 3×2 (iPhone+iPad) ✓

| Bullet | Status | Notes |
|---|---|---|
| FR-2.1 ingest Watch workouts + HR, no double-entry | ✅ | `CardioView` sync → `ingest` dedup by HK UUID |
| FR-2.2 iPhone GPS outdoor / manual indoor recording | ✅ | `CardioRecorder` + `LocationTracker`, `RecordCardioView` |
| FR-2.3 pair BLE chest strap, live HR | ✅ | `HeartRateMonitor` (0x180D), connect during recording |
| FR-2.4 live metrics (time/distance/pace/HR/zone/cal) | ✅ | `CardioMath` zones+pace+calories, metric tiles |
| FR-2.5 save HKWorkout (route + HR) | ✅ | `saveCardioWorkout` + `saveRecordedCardio` (HK-linked) |

> v1 scope note: REQUIREMENTS §8 defers on-device GPS/chest-strap cardio to v3.
> Implemented here behind protocol abstractions with deterministic simulator
> fakes so the flows are real and UI-tested; real CoreLocation/CoreBluetooth
> paths are wired for device runs.

## FR-3 Daily activity & steps — ✅ COMPLETE
Branch `feat/fr3-steps`. UI 2×2 (iPhone+iPad) ✓

| Bullet | Status | Notes |
|---|---|---|
| FR-3.1 read steps from HealthKit | ✅ | `HealthKitProvider` step sum; `TodayView` |
| FR-3.2 prominent steps + goal ring + 7-day trend | ✅ | `StepRing` + Swift Charts trend |
| FR-3.3 flights / distance / active energy | ✅ | activity tiles from `DayActivity` |

## FR-4 Data, HealthKit & sensors — ⏳ pending
## FR-5 History, PRs & trends — ⏳ pending
## FR-6 Migration & export — ⏳ pending
