# FR-2.1 — Auto-ingest Apple Watch workouts + HR from HealthKit

> Automatically ingest Apple Watch workouts (running, cycling, swimming,
> boxing/HIIT) and their heart-rate samples from HealthKit; no double-entry.

## Design
- `HealthDataProviding.newWorkouts(since:)` returns `IngestedWorkout`s (mapped
  from `HKWorkout` via `HealthKitProvider`). The simulator has none, so the fake
  provides one deterministic Watch run.
- `WorkoutRepository.ingest` de-duplicates by HealthKit UUID (UC-2 alt 2b) and
  stores HR samples. `lastHealthSync` (UserDefaults) bounds incremental reads.

## Mockups
Cardio tab: a "Sync from Apple Health" button and a workout history list. New
Watch workouts appear with type, distance, duration, avg HR.

## Implementation
1. `CardioView` list of `CardioWorkout` + "Sync from Apple Health" action that
   calls `health.newWorkouts(since:)` → `ingest` → updates `lastHealthSync`.
2. Auto-sync on first appearance.
- a11y ids: `cardio.sync`, `cardioRow.<type>`.

## Automated testing
- **Integration:** `ingest` de-dups by UUID, stores HR. (Done.)
- **UI:** launch, open Cardio, tap Sync; assert a run row appears; tap Sync
  again; assert no duplicate row.
