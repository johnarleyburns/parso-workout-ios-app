# Phase 7 — Add conditional HR detail to watch cardio summary

## Required behavior

After cardio completion, show an HR-over-time graph plus maximum and average HR
when HR tracking produced samples. If HR was disabled or no samples exist, show
no HR heading, graph, maximum, average, or placeholders.

## Implementation

- Extend the summary input/persisted completion envelope to carry timestamped HR
  samples. Reuse the phone's zone semantics and chart preparation/downsampling
  rules through shared `CadenceFeatures` logic where possible.
- Render a watch-sized Swift Charts line graph in `WatchCardioSummaryView`, with
  elapsed-time x-axis and zone-aware or otherwise phone-consistent styling.
- Compute average and maximum from validated samples in one pure presenter;
  ignore invalid BPM values and handle a single sample without divide-by-zero or
  an empty chart crash.
- Keep the summary scrollable on small watches and ensure phase 3 sync sends the
  same samples/metrics shown locally.

## Tests and acceptance

- Unit-test empty/disabled/invalid/single/multiple samples, average/max, ordering,
  and downsampling endpoint preservation. Extend watch smoke for HR-present and
  HR-absent summaries.
- Hardware-check chart readability after a real tracked workout.
- Acceptance: tracked workouts show graph + Avg + Max; untracked/no-sample
  workouts show nothing about HR.

