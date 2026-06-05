# FR-4.3 — Write summary strength workouts to HealthKit

> Write summary strength workouts to HealthKit (duration, energy,
> `.traditionalStrengthTraining`) for unified history; keep detailed set data
> local.

## Design
- `HealthDataProviding.saveStrengthWorkout(StrengthWorkoutSummary)` builds an
  `HKWorkout` via `HKWorkoutBuilder` with `.traditionalStrengthTraining`,
  duration, and active energy. The session stores the returned HK UUID
  (`healthKitWorkoutUUID`) so it isn't re-ingested.

## Mockups
Session screen toolbar → "Save to Apple Health" → confirmation.

## Implementation
1. `SessionView` toolbar action computes the summary (start = first set, end =
   last set, est. energy) and calls `saveStrengthWorkout`.
2. Stores the HK UUID on the session; shows a confirmation.
- a11y ids: `session.saveHealth`, `session.healthSaved`.

## Automated testing
- **UI:** log a set, tap "Save to Apple Health", assert a saved confirmation
  appears (fake records the summary).
