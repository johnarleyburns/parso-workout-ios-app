# FR-5.3 — Cardio history with HR overlay, pace splits, route map

> Cardio history with HR overlay, pace splits, and route map.

## Design
- `CardioDetailView` (FR-2) shows summary, an HR line chart, and an `MKMap`
  route polyline. Adds per-kilometer pace splits computed from route samples.
- Cardio history list lives in the Cardio tab (FR-2.1).

## Mockups
Cardio → workout → summary tiles, HR chart, route map, splits list.

## Implementation
1. Add `CardioMath`/route-based km splits to `CardioDetailView`.
- a11y ids: `cardioDetail.hrChart`, `cardioDetail.map`, `cardioDetail.splits`.

## Automated testing
- **Integration:** `GeoMath.pathDistance` + `CardioMath` pace. (Done.)
- **UI:** sync a Watch run (has HR), open its detail; assert the HR chart shows.
