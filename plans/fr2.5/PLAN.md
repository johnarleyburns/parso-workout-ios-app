# FR-2.5 — Save recorded workouts back to HealthKit

> Save recorded workouts back to HealthKit as `HKWorkout` (with route and HR
> samples) so they appear system-wide and close Activity rings.

## Design
- `HealthDataProviding.saveCardioWorkout(CardioWorkoutSummary)` builds an
  `HKWorkout` via `HKWorkoutBuilder` with energy, distance, and HR samples
  (route persisted locally; HK route via `HKWorkoutRouteBuilder` is a later
  refinement). The fake records the summary for assertions.
- `WorkoutRepository.saveRecordedCardio` stores the workout locally with the HK
  UUID so a later HealthKit ingest won't double-count (FR-2.1 dedup).

## Mockups
On End, the workout is saved and appears in the Cardio history list with an
"Apple Health" provenance.

## Implementation
1. On End → `saveCardioWorkout` (HK) then `saveRecordedCardio` (local, linked).
2. History row shows source.
- a11y ids: `record.end`, reuse `cardioRow.<type>`.

## Automated testing
- **Integration:** `saveRecordedCardio` computes avg/max HR, links HK UUID;
  re-ingest with same UUID is a no-op. (Covered by repo tests + new test.)
- **UI:** record → end → assert the workout appears in Cardio history.
