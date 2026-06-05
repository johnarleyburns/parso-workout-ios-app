# FR-1.5 — Rest timer between sets (auto-start on completion)

> Rest timer between sets, auto-startable on set completion.

## Design
- A lightweight `RestTimerModel` (`@Observable`) tracks `remaining`, `isRunning`,
  driven by a SwiftUI `TimerView` using a 1s `Timer.publish`. Default duration
  from Settings (`restSeconds`, default 90).
- Auto-starts when a set is logged (configurable via a toggle). User can skip,
  +30s, or reset. Completion fires a haptic.

## Mockups
A pill at the top of the session ("Rest · 0:47" with Skip) matching the mockup;
counts down and dismisses at zero.

## Implementation
1. `RestTimerModel` + `RestTimerBar` view.
2. Trigger `start()` from `SetEditor` save when auto-rest is on.
3. Settings: rest duration stepper + "auto-start rest" toggle.
- a11y ids: `rest.bar`, `rest.skip`, `rest.add30`, `rest.remaining`.

## Automated testing
- **Unit:** `RestTimerModel` start/tick/skip/add — logic is time-injectable
  (decrement via a `tick()` method, not wall-clock, so it's deterministic).
- **UI:** log a set with auto-rest on; assert the rest bar appears; tap Skip;
  assert it disappears.
