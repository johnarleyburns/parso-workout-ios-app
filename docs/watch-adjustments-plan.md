# Watch Adjustment Plan

## Goal

Implement all requested Apple Watch fixes as one phase: lock recovery, independent weight and distance units, Live HR cleanup, summary cleanup, simplified cardio GPS setup, built-in HIIT picker, simplified boxing pickers, rowing GPS, verification, self-review, commit, merge to `main`, push, and confirm checks are green.

This document is the implementation handoff. The implementing agent should make every code change in a single cohesive pass, then review the final diff against this file before committing.

Static HTML mockups for the target watch screens are written to `docs/watch-adjustments-mockups.html`. Keep that file aligned with any reviewed changes to this plan.

## Current Implementation Notes

- Watch UI entry points are concentrated in `Cadence/Cadence Watch App Watch App`.
- Cardio setup currently lives in `WatchCardioSetupView`.
- Live HR currently lives inside `WatchRootView`.
- Active cardio display and controls are split across `WatchCardioSessionView`, `WatchCardioView`, and `WatchCardioControlsView`.
- Watch summary currently lives in `WatchCardioSummaryView`.
- Unit state currently uses `MeasurementUnitPreference` for both strength weight and cardio distance formatting.
- Watch sync preferences currently live in `CadenceCore/Sources/CadenceFeatures/WatchSync.swift`.
- Cardio formatting and interval setup models currently live in `CadenceCore/Sources/CadenceFeatures/WatchCardioModels.swift`.
- Built-in interval factories already exist in `CadenceCore/Sources/CadenceCore/IntervalPlan.swift`.

## Mockups

### Units

```text
Units

Weight
  [x] Pounds (lb)
  [ ] Kilograms (kg)

Distance
  [x] Miles (mi)
  [ ] Kilometers (km)
```

Weight and distance are independent. Any combination is valid:

- Pounds + miles
- Pounds + kilometers
- Kilograms + miles
- Kilograms + kilometers

### Live HR

```text
Live HR

Z1 / Recovery
      92
[zone bars]

[Start monitoring]
```

When monitoring is not active, do not show an extra top status label and do not show explanatory text below the button.

### Run / Walk / Cycle / Swim / Rowing Setup

```text
Run

GPS  [on]

[Start run]
```

Use the same pattern for Walk, Cycle, Swim, and Rowing. The workout name and start button label should match the selected activity.

### Workout Summary

```text
      checkmark

Total        0:00:42
Avg HR           128
Distance       0.12 mi
Laps               4

[Save]
Discard
```

The time value must have enough room that `0:00:00` and longer durations do not clip on watch sizes.

### HIIT Setup

```text
HIIT

Protocol
Tabata

[Start]
```

The only editable value is the selected built-in protocol. Warmup, work, rest, cooldown, rounds, and set structure are fixed by the selected protocol.

### Boxing Setup

```text
Boxing

Rounds   8
Round    3 min
Rest     60 sec

[Start]
```

No warmup. No cooldown.

## Required Behavior Changes

### 1. Lock Recovery

- Remove the app-owned locked overlay and local `isLocked` state in `WatchCardioSessionView`.
- The `Lock` button should call `watchManager.enableWaterLock()` only.
- Do not replace the active workout pages with a SwiftUI "Screen locked" overlay.
- Acceptance: after the user unlocks Apple Watch Water Lock, the workout UI is still present and immediately usable without force quitting.

### 2. Independent Watch Units

- Add a new `DistanceUnitPreference` model with `kilometers` and `miles`.
- Keep `MeasurementUnitPreference` as the strength/weight preference.
- Add `AppSettings.distanceUnit`, persisted as `settings.distanceUnit`.
- Default distance unit should follow the current locale behavior where possible:
  - US locale defaults to miles.
  - Non-US locale defaults to kilometers.
- Preserve existing weight unit behavior.
- Update `WatchUnitsView` to show separate Weight and Distance sections.
- Existing `set_unit` watch message remains weight-only.
- Add a distance-unit watch message, for example `set_distance_unit`, for iPhone setting sync from Watch.
- Update `WatchSync.Preferences` and context dictionaries to include distance unit.
- Update import/export preferences if the app already round-trips user settings through exports.

### 3. Cardio Formatting Uses Distance Unit

- Update `CardioMetricsModel` so distance, pace, and speed are based on `DistanceUnitPreference`, not weight unit.
- Preserve weight unit where strength/watch strength flows need it.
- Distance formatting:
  - Kilometers: show meters below 1000 m, kilometers at 1000 m and above.
  - Miles: show miles.
- Pace formatting:
  - Kilometers: `/km`.
  - Miles: `/mi`.
- Speed formatting:
  - Kilometers: `km/h`.
  - Miles: `mph`.
- Rowing split remains `/500m`.

### 4. Live HR Cleanup

- Remove text below `Start monitoring`.
- Remove the top idle text currently shown as `Not monitoring`, which can truncate as `..t monitoring`.
- Keep the navigation title `Live HR`.
- Place the zone label below the title area and above the BPM number.
- Zone label must include zone number and name:
  - `Z1 / Recovery`
  - `Z2 / Endurance`
  - `Z3 / Tempo`
  - `Z4 / Threshold`
  - `Z5 / Max`
- Keep existing zone colors and bar visualization unless layout requires minor spacing adjustments.

### 5. Workout Summary Cleanup

- Remove the `Active kcal` row entirely.
- Rename `Duration` to `Total`.
- Rename `Avg / Max HR` to `Avg HR`.
- Show only the average HR number on the right side.
- Do not show max HR on this summary screen.
- Give the duration value enough width and scaling so it does not clip to the right.
- Keep Save and Discard actions.

### 6. Run / Walk / Cycle Setup

- Replace the `Outdoor` and `Indoor` buttons with a single `GPS` toggle.
- Toggle default is on.
- GPS on maps to `.outdoor`.
- GPS off maps to `.indoor`.
- Remove the `GPS + pedometer distance. Auto-pauses when you stop.` text.
- Preserve existing start labels: `Start run`, `Start walk`, `Start cycle`.

### 7. Swim Setup

- Remove `Pool` and `Open water` controls.
- Remove lap-length controls.
- Remove `Laps count automatically. Water Lock turns on at start.` text.
- Add a `GPS` toggle, default on.
- GPS on maps to `.openWater`.
- GPS off maps to `.pool(lapLength: 25)` only as an internal HealthKit fallback.
- Do not expose pool/open-water language in the UI.

### 8. HIIT Setup

- Remove editable warmup, rounds, round, rest, and cooldown rows for HIIT.
- Replace with one picker for built-in protocols only.
- Default selection is `Tabata`.
- Include these protocols:
  - `Tabata`
  - `Norwegian 4x4`
  - `Gibala`
  - `SIT (Wingate)`
  - `REHIT`
  - `10-20-30`
- Start should use existing built-in `IntervalPlan` factories with their default durations and structures.
- Do not allow editing warmup, work, rest, cooldown, rounds, sets, or reps from the Watch HIIT screen.

### 9. Rowing Setup

- Add the same `GPS` toggle pattern as Run/Walk/Cycle.
- Toggle default is on.
- GPS on maps to `.outdoor`.
- GPS off maps to `.indoor`.
- Preserve start label `Start row`.

### 10. Boxing Setup

- Remove existing warmup, cooldown, and free-form interval settings.
- Replace with exactly three pickers:
  - `Rounds`: values `1...20`, default `8`.
  - `Round`: values `2 min` and `3 min`, default `3 min`.
  - `Rest`: values `30 sec` and `60 sec`, default `60 sec`.
- Start should use `IntervalPlan.boxing(rounds:round:rest:)`.
- No warmup phases.
- No cooldown phases.

## Suggested Implementation Shape

- Add `DistanceUnitPreference` near `MeasurementUnitPreference` in core model code.
- Add a small distance unit default helper in the same style as `WeightIncrement.unitDefault()`.
- Extend `AppSettings` with `distanceUnit` and include it in UI-test defaults cleanup.
- Extend `WatchSync.Key` and `WatchSync.Preferences` with distance unit.
- Update `WatchWorkoutManager.applySettingsContext` if it applies watch sync preferences into `AppSettings`.
- Update iPhone-side watch message handling in `AppModel` so Watch can send distance-unit changes independently from weight-unit changes.
- Update `WatchUnitsView` to send weight and distance changes separately.
- Update `CardioMetricsModel` initializer and call sites:
  - Existing strength code keeps using `MeasurementUnitPreference`.
  - Cardio code passes both `watchSettings.unit` and `watchSettings.distanceUnit`.
- Consider a compatibility initializer only if it avoids broad churn in existing tests.
- Replace `WatchIntervalSetupView` internals with mode-specific UI:
  - HIIT protocol picker.
  - Boxing three pickers.
  - If any non-HIIT/non-boxing call site remains, keep a minimal fallback or remove only after confirming there are no callers.
- Keep SwiftUI layout compact and watch-friendly. Use fixed/trailing value columns where summary rows can clip.

## Logical Tests

Run logical tests where practical. Do not add simulator tests beyond the existing watch smoke test.

### CadenceFeatures / Core Tests

Add or update `WatchCardioModelsTests`:

- Kilograms weight + miles distance formats distance as miles.
- Pounds weight + kilometers distance formats distance as meters/kilometers.
- Pace label follows distance unit only.
- Speed label follows distance unit only.
- Rowing split remains `/500m`.

Add or update `WatchSyncTests`:

- Context applies distance unit.
- Context dictionary round-trips weight and distance independently.
- Invalid distance unit preserves the existing preference.
- Missing distance unit preserves defaults.

Add or update interval tests:

- HIIT setup defaults to Tabata.
- Each HIIT picker option maps to the intended built-in `IntervalPlan` factory.
- Boxing defaults to 8 rounds, 3 min round, 60 sec rest.
- Boxing plan has no warmup and no cooldown.
- Boxing rounds are limited to `1...20`.
- Boxing round length only permits 2 or 3 minutes.
- Boxing rest only permits 30 or 60 seconds.

### UI / Smoke

- Run the existing watch smoke test only.
- Do not add broader simulator coverage for this task.

## Verification Commands

Use the repo's established commands where available:

```sh
swift test
```

Run the existing watch smoke test using the existing project/test command already used in this repo. Do not broaden simulator coverage beyond that smoke test.

## Self-Review Checklist

Before committing, review the implementation against this document line by line:

- [ ] Lock no longer traps the app behind a SwiftUI overlay.
- [ ] Weight and distance units are independent.
- [ ] Watch Units screen exposes both sections.
- [ ] Watch sync carries distance unit.
- [ ] Live HR has no idle explanatory copy and no `Not monitoring` label.
- [ ] Live HR zone label says `Z# / Name` and sits above BPM.
- [ ] Summary has no `Active kcal`.
- [ ] Summary says `Total`.
- [ ] Summary says `Avg HR` and shows only one HR number.
- [ ] Duration value does not clip.
- [ ] Run/Walk/Cycle use GPS toggles default on.
- [ ] Swim uses GPS toggle default on and hides pool/lap copy.
- [ ] Rowing has GPS toggle default on.
- [ ] HIIT has only a built-in protocol picker.
- [ ] Boxing has exactly the three requested pickers.
- [ ] Logical tests cover changed models.
- [ ] Existing watch smoke test passes.

Fix every gap found in the checklist before committing.

## Agentic Handoff Instructions

1. Create a feature branch from current `main`.
2. Keep `docs/watch-adjustments-mockups.html` as the visual reference and update it if implementation decisions change during review.
3. Implement all changes above as one phase.
4. Run logical tests.
5. Run only the existing watch smoke test for simulator/UI coverage.
6. Review the final diff against this plan, the HTML mockups, and the checklist.
7. Fix any implementation gaps.
8. Commit with a concise message, for example `Fix watch workout setup and summary UI`.
9. Merge the feature branch back to `main`.
10. Push `main`.
11. Check GitHub/CI status and confirm the UI/checks are green.

## Assumptions

- "GPS default on" means each relevant setup screen starts with GPS enabled unless a future requirement explicitly asks to persist per-workout GPS choices.
- Swim GPS off uses `.pool(lapLength: 25)` internally only because HealthKit needs a non-open-water fallback; the UI must not expose lap length or pool/open-water choices.
- "UI is green" means the pushed `main` branch has passing GitHub checks/status for the app's configured workflows.
- This task does not remove HealthKit active energy collection globally; it only removes kcal from the watch summary UI.
