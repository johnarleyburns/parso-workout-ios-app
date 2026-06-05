# FR-3.1 — Read daily step count from HealthKit

> Read daily step count from HealthKit (iPhone pedometer works without a watch).

## Design
- `HealthDataProviding.todayActivity()` returns a `DayActivity` (steps, distance,
  flights, active energy). `HealthKitProvider` sums `HKQuantityType.stepCount`
  for the current day via `HKStatisticsQuery`. The fake returns a seeded count
  (`-todaySteps N` launch arg) for deterministic UI tests.

## Mockups
Today tab shows the current step count prominently (matches the "Steps" card).

## Implementation
1. `TodayView` loads `todayActivity()` in `.task` and on appear.
2. Step count rendered large.
- a11y id: `today.steps`.

## Automated testing
- **UI:** launch with `-todaySteps 8200`; open Today; assert the steps label
  shows 8,200.
