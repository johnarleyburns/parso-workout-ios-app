# FR-4.1 — Least-privilege HealthKit authorization with in-context priming

> Request least-privilege HealthKit read/write authorization with clear
> in-context priming before the system sheet.

## Design
- A priming sheet explains *why* Cadence needs Health access before the system
  permission dialog appears (NFR-3 clear purpose). On "Continue", the app calls
  `HealthDataProviding.requestAuthorization()` which requests only the needed
  read/write types. Status is surfaced afterward.

## Mockups
Settings → "Apple Health" row → priming sheet (icon, bullet list, Continue) →
system sheet → status (Connected/Not connected).

## Implementation
1. `HealthPrimingView` sheet from Settings.
2. Settings shows current status.
- a11y ids: `settings.health.connect`, `health.priming.continue`,
  `settings.health.status`.

## Automated testing
- **UI:** open Settings → Apple Health → priming sheet shows → Continue →
  status shows "Connected" (fake auto-authorizes).
