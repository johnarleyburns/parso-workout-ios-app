# FR-2.4 — Live metrics during recording

> Show live metrics during recording: elapsed time, distance/pace, current HR,
> HR zone, calories estimate.

## Design
- `CardioRecorder` exposes `elapsed`, `distanceMeters`, `currentBPM`, derived
  `pace`, `zone` (`CardioMath.hrZone`), and `calories`
  (`CardioMath.estimateCalories`), updated on a 1s tick.

## Mockups
Live screen grid: Time · Distance · Pace · HR · Zone · Calories (the Boxing
mockup shows Time/Calories/Avg HR/Max HR + zone band).

## Implementation
1. Metric tiles bound to `CardioRecorder`.
2. Zone band colored by zone.
- a11y ids: `record.elapsed`, `record.distance`, `record.pace`, `record.hr`,
  `record.zone`, `record.calories`.

## Automated testing
- **Unit:** zone bands, pace, calorie estimate. (Done — `CardioMathTests`.)
- **UI:** during a recording, assert elapsed/calories tiles render and update.
