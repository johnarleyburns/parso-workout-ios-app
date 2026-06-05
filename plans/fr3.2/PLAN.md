# FR-3.2 — Steps prominent with goal ring + 7-day trend

> Surface steps prominently on the home screen with a goal ring and 7-day trend.

## Design
- `StepRing` view draws progress = todaySteps / `settings.stepGoal` (default
  10,000). A `Chart` shows the last 7 days from `activityTrend(days:7)`.

## Mockups
Today: a circular goal ring around the step count, then a 7-day bar chart.

## Implementation
1. `StepRing` (Shared) with accessible label.
2. `TodayView` 7-day `Chart` (BarMark) below the ring.
- a11y ids: `today.goalRing`, `today.trendChart`.

## Automated testing
- **UI:** open Today; assert the goal ring and 7-day trend chart exist.
