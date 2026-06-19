# Phase 1 — HR Gate Fix + Toggle

## Problem
- `PreWorkoutHRView` renders twice for outdoor cardio (Home gate + `OutdoorCardioView.showingHRGate`)
- Same for indoor cardio (`RecordCardioView`) and intervals (`IntervalView`)
- No persistent preference — HR gate shown every time regardless of user intent

## What the code does today
- `HomeView` line 196: renders `PreWorkoutHRView` as an overlay whenever `hrGateKind != nil`
- `OutdoorCardioView` line 29: `@State private var showingHRGate = true` — always shows its own gate on appear
- `RecordCardioView` line 24: `@State private var showingHRGate: CardioType? = nil` — set in `onAppear` if `initialType` exists
- `IntervalView` line 28: `@State private var showingHRGate = true` — always shows its own gate
- No HR preference in `AppSettings`

## Design

### 1. Add `useHRMonitoring` to `AppSettings`
```
var useHRMonitoring: Bool  // UserDefaults key: "settings.useHRMonitoring"
// Default: false
// Once user changes it, remembered forever
```

### 2. Remove per-view HR gates
- **`OutdoorCardioView`**: Remove `showingHRGate` state and the `PreWorkoutHRView` branch. Accept `captureHR: Bool` as init parameter (passed from Home's routing).
- **`RecordCardioView`**: Same — remove internal HR gate, accept `captureHR: Bool`.
- **`IntervalView`**: Same — remove internal HR gate, accept `captureHR: Bool`.

### 3. Centralize HR gate in HomeView (conditional)
- In `HomeView`, the HR gate overlay (`hrGateKind`) only renders if `settings.useHRMonitoring` is true.
- If `useHRMonitoring` is false, `proceedFromHRGate` is called immediately with `useHR: false`.
- When launching outdoor/indoor/interval, pass `captureHR` through to the view.

### 4. Simplify PreWorkoutHRView
- Remove "Continue without HR" button — if they opted into HR, they see the connection screen with just a green "Start" button.
- If they can't connect, they can go back (dismiss) or press "Start" anyway (HR will still try to connect during workout if strap is remembered).

### 5. HR toggle placement
- For now (Phase 1): the toggle lives on a new small section at the bottom of the pre-workout settings screens:
  - Strength: `WeightsStartView` (bottom section)
  - Cardio outdoor: `CardioGoalSheet` (bottom section)
  - Cardio indoor: `RecordCardioView` activity picker (bottom section)
  - Intervals: `IntervalSetupView` (bottom section)
  - Swim: `SwimRecordView` (bottom section, even though swim doesn't use HR today)
- Toggle label: "Use HR monitoring (watch/strap)"
- Toggle reads from / writes to `settings.useHRMonitoring`

### 6. Remove "Connect HR Strap" from active workout views
- `SessionView`: remove any "Connect HR Strap" button/row (if present)
- `OutdoorCardioView`: remove any mid-workout HR connection affordance
- `RecordCardioView`: same
- The only way to connect HR is before the workout starts

## Files touched
| File | Change |
|------|--------|
| `AppSettings.swift` | Add `useHRMonitoring: Bool` |
| `HomeView.swift` | Conditionally skip HR gate; pass `captureHR` to cardio views |
| `PreWorkoutHRView.swift` | Remove "Continue without HR" button; just "Start" |
| `OutdoorCardioView.swift` | Remove internal HR gate; accept `captureHR` param |
| `RecordCardioView.swift` | Remove internal HR gate; accept `captureHR` param |
| `IntervalView.swift` | Remove internal HR gate; accept `captureHR` param |
| `WeightsStartView.swift` | Add HR toggle at bottom |
| `CardioGoalSheet.swift` | Add HR toggle at bottom |
| `IntervalSetupView.swift` | Add HR toggle at bottom |
| `SessionView.swift` | Remove "Connect HR Strap" if present |

## Testing
- `swift test` (CadenceCore — no UI changes there)
- `xcodebuild` iOS build verification
- Manual: Start outdoor run → should see HR gate only once (if toggle on) or not at all (if toggle off)
- Manual: Start strength → same
- Manual: Start HIIT → same
