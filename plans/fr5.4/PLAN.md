# FR-5.4 — Calendar/heatmap of training consistency

> Calendar/heatmap of training consistency.

## Design
- `WorkoutRepository.trainingDays` returns the set of day-stamps with sessions.
  A `ConsistencyHeatmap` view renders the last ~16 weeks as a GitHub-style grid,
  shading days that have a workout.

## Mockups
Trends → "Consistency" section: a week-by-week grid of filled/empty squares.

## Implementation
1. `ConsistencyHeatmap` (Shared) from `trainingDays`.
2. `TrendsView` "Consistency" section.
- a11y ids: `trends.consistency`.

## Automated testing
- **Integration:** `trainingDays` dedups same-day sessions. (Done.)
- **UI:** seed history; open Trends; assert the consistency grid renders.
