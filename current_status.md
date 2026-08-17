# Current Status

Updated: 2026-08-16

## Field-testing follow-up

This follow-up addresses the remaining UI issues found after the Home field test:

- Watch sync feedback is inset below the safe area so the startup toast is fully visible.
- Home Start Workout and Log Previous Workout use the same 20-point section spacing as the surrounding Home sections.
- Start Workout now labels the just-in-time editing route `Custom Workout`.
- Workout Plan puts its full-width `Start Workout` control above the list as a standalone action.
- Productive Coach volume suggestions whose insight says `volume is on track` use the green positive treatment; low/high volume remains warning-colored.

Focused presenter and iPhone smoke coverage verify the productive-volume tone and custom-workout label. The CI smoke job covers the complete navigation surface.

## Home field-testing checklist

The Home View field test identified these issues, which are the acceptance criteria for this batch:

1. Rename the Coach suggestion workout to `Suggested Workout` and use the subtitle `Coach created a Workout created to close gaps for this week`.
2. Make `This Week` expand in place. On expansion, hide the `Weekly Volume` heading, start with `Legs`, and put `Show less` at the bottom. Capitalize `Coach’s Suggestions`; keep each suggestion collapsed by default, independently expandable, and color-coded green for positive, yellow for warning, and white for neutral.
3. Apply the same green/yellow state color coding to Weekly Volume body-part rows.
4. Remove the separate `What you did` section. Put this week’s Strength and Cardio workout details inside expanded `This Week`, add `View more…` for complete history, then show weekly volume and `Show less`.
5. Make Strength `Quick Start` enter warm-up/the workout directly without the plan or settings surface.
6. Make Home `Start Workout` full width and put `Log Previous Workout` below it; use Progress View’s Full History for complete history.

## Implementation status — complete

- Home now uses one expandable This Week card for workout details, history navigation, and weekly volume.
- Coach suggestions use the requested copy, independent expansion, and semantic positive/warning/neutral colors.
- Quick Start bypasses plan/settings UI and enters the configured warm-up or active strength session.
- Home actions have the requested layout; duplicate Home Workout History remains removed because Progress View owns Full History.
- Presenter unit coverage now verifies weekly grouping and suggestion/body-part state mapping.
- The iPhone smoke test verifies Home expansion, plan navigation, direct Quick Start, no settings surface, workout completion, and summary return.

## Final audit

- [x] Suggested Workout copy and the requested gap-closing subtitle are present.
- [x] This Week expands in place; Show more is replaced by Show less, the expanded volume starts with Legs, and there is no Weekly Volume heading in the Home composition.
- [x] Coach’s Suggestions is capitalized; suggestions are independently expandable, collapsed by default, and tone-coded.
- [x] Weekly Volume rows use green for productive range and yellow for below/above range.
- [x] What you did is no longer a Home section; expanded This Week contains Strength and Cardio, complete-history navigation, volume, total volume, and Show less.
- [x] Strength Quick Start bypasses plan/settings UI and enters warm-up or the active workout.
- [x] Start Workout is full width, Log Previous Workout is below it, and Home does not duplicate Progress View’s Full History.

## Verification

- `swift test --package-path CadenceCore`: 1,318 tests passed.
- `make ci`: build, 1,318 tests, test-pyramid guardrails, and no-network guardrail passed.
- `make smoke`: WatchConnectivity regression and iPhone Home/Quick Start smoke passed.
- `git diff --check`: passed.
- Commit `ab68140` (`Implement Home field testing fixes`) is pushed to `main`.
- [GitHub Actions run 31962467272](https://github.com/johnarleyburns/parso-workout-ios-app/actions/runs/31962467272) passed `core-tests`, archive warning checks, IPA export, and TestFlight upload.
