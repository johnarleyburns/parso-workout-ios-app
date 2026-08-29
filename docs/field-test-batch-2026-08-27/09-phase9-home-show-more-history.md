# Phase 9 — Link Home Completed Workouts to full History

## Required behavior

Add a `Show more…` link at the bottom of Home's Completed Workouts card. It opens
the full workout History page.

## Implementation

- Add the link as the final row inside the existing Completed Workouts card,
  separated consistently from workout rows. Keep it visible when the card has
  completed entries; decide empty-state visibility from existing card semantics,
  but never show a dead link.
- Route through the app's canonical full `HistoryView`, using the same navigation
  state as the History tab/destination so filters, refresh, and subsequent Back
  behavior are consistent. Do not create a second history implementation.
- Use visible text `Show more…` and accessibility identifier
  `home.completed.showMore`.

## Tests and acceptance

- Unit-test Home presenter/router visibility and destination. Extend iPhone
  smoke to complete or seed a workout, tap Show more, assert full History, open
  the workout, and return using phase 8's Back action.
- Acceptance: one tap from the bottom of Completed Workouts opens the complete,
  refreshed workout history.

