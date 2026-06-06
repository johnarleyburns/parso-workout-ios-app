# FR-5.2 — PR timeline per exercise + global recent PRs

> PR timeline per exercise and a global "recent PRs" view.

## Design
- `WorkoutRepository.prTimeline(for:rule:formula:)` returns progressive records
  (each new all-time best). `recentPRs` returns the best set per exercise across
  the library, newest first.

## Mockups
Trends top: "Personal Records" list (Heaviest / Best volume with dates), matching
the mockup. Each exercise detail shows PR markers on the chart + a PR list.

## Implementation
1. `TrendsView` "Recent PRs" section from `recentPRs`.
2. `ExerciseTrendView` PR markers (`PointMark`) + PR timeline list.
- a11y ids: `trends.recentPRs`, `recentPR.<name>`, `trend.prList`.

## Automated testing
- **Integration:** `prTimeline` progressive-only; `recentPRs` ordering. (Done.)
- **UI:** seed history; open Trends; assert a recent-PR row exists.
