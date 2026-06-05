# FR-1.4 — Auto-detect & flag a new PR (configurable rule)

> Auto-detect and flag a new PR (configurable: 1RM estimate, top weight, or top
> volume).

## Design
- `PRCalculator.isNewPR` (pure) compares a candidate set against prior history
  under the selected `PRRule` (topWeight / estimated1RM / topVolume). A tie is
  not a PR (must strictly exceed).
- `WorkoutRepository.wouldBePR` wraps it against an exercise's history (excluding
  the current session so re-opening doesn't double count).
- Rule + 1RM formula come from Settings (`@AppStorage`, defaults: estimated1RM,
  Epley — resolves REQUIREMENTS §9 open questions).

## Mockups
On saving a PR set, a "PR" badge animates onto the set row (Reduce Motion
honored). A subtle haptic fires (`UINotificationFeedbackGenerator`).

## Implementation
1. On set save, call `wouldBePR`; if true, mark the set row with a PR badge and
   fire haptic.
2. Persist nothing extra — PRs are derived; the badge is computed from history.
- a11y id: `set.prBadge`.

## Automated testing
- **Unit:** `isNewPR` strict-exceed, warmup exclusion, empty history. (Done.)
- **UI:** seed a prior best; log a heavier set in a new session; assert a PR
  badge appears. Log a lighter set; assert no badge.
