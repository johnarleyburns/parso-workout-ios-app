# FR-3.3 — Flights, distance, active energy alongside steps

> Show flights climbed, walking/running distance, and active energy alongside
> steps.

## Design
- `DayActivity` already carries `flightsClimbed`, `distanceMeters`,
  `activeEnergyKcal`. `HealthKitProvider` sums each via `HKStatisticsQuery`.

## Mockups
Today: a row of metric tiles under the ring — Flights · Distance · Active Energy.

## Implementation
1. Metric tiles in `TodayView`.
- a11y ids: `today.flights`, `today.distance`, `today.energy`.

## Automated testing
- **UI:** open Today; assert the flights, distance, and energy tiles render.
