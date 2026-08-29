# Phase 6 — Refine watch cardio live metrics

## Required layout

- Elapsed time at the top.
- When HR monitoring is enabled: a same-size, bold, centered, zone-colored BPM
  value next. Do not show “HR” or “Heart Rate”. Use the same zone boundaries and
  semantic colors as iPhone.
- Distance at lower left as a compact value such as `132 m` or `2 mi`; no
  “Distance” label. Show it only when GPS was enabled for this workout.
- Do not show average HR during the live workout.

## Implementation

- Extract a pure `WatchCardioLivePresenter` in `CadenceFeatures` that returns
  display fields, visibility, compact distance text, and semantic HR zone. Map
  semantic zones to watch colors in the view.
- Make GPS-enabled and HR-enabled explicit session configuration, not inferred
  from a transient zero/nil sample. A GPS workout may show `0 m`; a non-GPS
  workout must show no distance even if HealthKit reports incidental distance.
- Update `WatchCardioSessionView` for small and large watch sizes and preserve
  pause/resume/end controls and accessibility labels even though visible metric
  labels are removed.

## Tests and acceptance

- Unit-test every HR zone/boundary, no-HR mode, GPS on/off, metric/imperial
  formatting, and nil/zero samples. Extend watch smoke with deterministic HR/GPS
  states and screenshot/accessibility assertions.
- Hardware-check legibility, truncation, zone transitions, and GPS-only distance.
- Acceptance: the live screen contains only the requested metrics and conditions;
  average HR is absent.

