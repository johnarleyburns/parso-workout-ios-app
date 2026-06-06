# FR-5.1 — Per-exercise history list & trend chart

> Per-exercise history list and trend chart (top weight, est. 1RM, volume over
> time).

## Design
- `WorkoutRepository.trendSeries(for:rule:formula:)` returns the best metric per
  training day. `ExerciseTrendView` charts it (Swift Charts) with a metric
  picker (Top weight / Est 1RM / Best set volume) and lists full set history.

## Mockups
Trends → exercise → metric segmented control, line chart with month axis, then
the set history (matches the "Bench Press / Top weight / Volume" mockup).

## Implementation
1. `TrendsView` lists exercises that have sets.
2. `ExerciseTrendView` metric picker + `Chart` + history list.
- a11y ids: `trends.exercise.<name>`, `trend.metric`, `trend.chart`,
  `trend.history`.

## Automated testing
- **Integration:** `trendSeries` best-per-day. (Done.)
- **UI:** seed history; open Trends → Bench Press; assert the chart and metric
  picker render; switch metric.
