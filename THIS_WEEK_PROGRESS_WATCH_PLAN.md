# This Week, Progress, and Apple Watch Responsiveness Plan

## Scope

Implement the requested field-test revisions in one pass without changing the
workout data model or CloudKit schema. This change is presentation/state
behavior plus Watch launch scheduling:

1. Restore a separate This Week `Muscle Group Volume` section.
2. Keep the muscle map as its own This Week section, expanded by default.
3. Persist each This Week section's expanded/collapsed state, including the map,
   for the next visit.
4. Rename Stair Climber to Stairs in user-facing cardio labels while preserving
   the existing raw value and stored-data compatibility.
5. Simplify and correct the Progress selector and make Personal Records exercise
   selection single-series rather than rendering every exercise at once.
6. Make the Apple Watch first-launch authorization boundary stable and keep
   WatchConnectivity/catalog work away from the first interactive frame and the
   authorization surface.

## Detailed implementation

### A. This Week sections and persisted disclosure state

- Extend `WeeklyDetailMode` with a `muscleGroupVolume` mode while retaining the
  existing modes for Strength and Cardio.
- Replace the single-selection `WeeklyDetailSelection` behavior with independent
  expansion flags for all This Week sections. The state must support the map,
  Muscle Group Volume, Strength, and Cardio being independently open or closed.
- Default the map section to expanded on first use. Default the other sections
  to their current collapsed state.
- Persist the four flags in `UserDefaults` under a namespaced key. Decode missing
  or invalid values to the defaults above, so existing installs upgrade safely.
- Bind the persisted value from `HomeView` into `HomeWeekDashboardSection`, and
  write changes only when a disclosure button is tapped. Do not persist workout
  data or add a schema migration for UI state.
- Keep the muscle-map front/back selector independent from section expansion;
  preserve its existing in-memory behavior unless the current page lifecycle
  already persists it.

### B. This Week volume presentation

- Keep `Sets per Muscle Group` as the muscle-map section title and render only
  the map/cardio affordance there. Remove the `Total Volume` row from that map
  content.
- Add a separate `Muscle Group Volume` section with a disclosure row and the
  existing legend, partner selector, science link, per-muscle rows, and total
  tonnage row.
- Render only the muscle groups already supplied by the dashboard volume
  projection; do not create zero-set rows for untracked groups.
- Sort rows by weekly set count descending, then displayed muscle name
  alphabetically, with a stable raw-value tie-break if needed.
- Preserve partner selection and warning behavior. The selected partner’s rows
  and tonnage must drive the section just as they do today.
- Add/adjust headless tests for descending-set ordering and deterministic ties,
  plus UI identifiers for the restored section and total volume.

### C. Cardio naming

- Change only `CardioType.stairClimber.displayName` and
  `WorkoutType.stairClimber.displayName` from `Stair Climber` to `Stairs`.
- Leave raw values, decoding aliases, HealthKit mapping, symbols, and persisted
  records untouched. Add tests proving the raw value remains compatible and the
  visible label is `Stairs`.

### D. Progress selector and Personal Records

- Remove `cardioChange`, `frequency`, and `muscleVolume` from the user-facing
  `ProgressQuestion` cases and display ordering. Remove their dead rendering
  branches and unused cards from the Progress flow.
- Rename `trends` to `personalRecords` at the feature-model level if safe for
  persisted/UI identifiers; otherwise retain the raw value for compatibility
  and expose `Personal Records` as its display name. Use one consistent
  accessibility identifier for the renamed surface.
- Keep the remaining selector alphabetized by display name after the removals.
- Ensure Consistency is rendered as one card only; do not put the already-carded
  Consistency view inside another section/card wrapper.
- Refactor `PRTimelineView` to build one exercise selector from the available PR
  event exercise names. Select the first exercise deterministically by name (or
  preserve the current selection while the view remains mounted).
- Render only the selected exercise’s PR timeline in the chart, with its latest
  record summary and share action. Changing the dropdown replaces the series;
  it must not render all exercise series simultaneously.
- Keep the empty state and citation, and add headless tests for the filtered
  single-exercise series/selection support where practical.

### E. Apple Watch first launch and sync responsiveness

- Do not mark the initial health authorization boundary resolved merely because
  `HKHealthStore.requestAuthorization` returned. The authorization view must
  remain visible after the system sheet closes until the user explicitly chooses
  to continue.
- On a successful/partial authorization result, show a stable continuation state;
  on denial, keep both retry and continue-without-heart-rate actions available.
- Make both Allow and Continue actions resolve the boundary exactly once and
  then start post-launch WatchConnectivity setup.
- Gate `activateWCSession`, active-workout recovery, settings injection, and
  catalog seeding behind the resolved authorization boundary. This guarantees
  the first visible Watch surface is the permission boundary and prevents sync
  work from competing with it.
- After the boundary, yield once before activation and run catalog preparation
  at utility priority in its detached context as it does today.
- Parse incoming WatchConnectivity property-list data (preferences, today plan,
  and custom exercise rows) into a Sendable snapshot off the main actor. Apply
  only the small observable state update on the main actor.
- Defer custom-exercise SwiftData reconciliation until after the first launcher
  frame, and avoid doing it from the permission surface. Preserve existing
  records and save behavior.
- Add Watch tests for: authorization remains unresolved after request return;
  explicit continuation resolves it; and context parsing preserves plan,
  preferences, and custom exercises.

## Audit checklist

- This Week has exactly four independently expandable sections, with the map
  expanded by default on a fresh install and each state restored on return.
- `Muscle Group Volume` rows are descending by sets, tie-broken alphabetically,
  and `Total Volume` appears only there.
- The visible cardio label is `Stairs`; stored raw values and decoding aliases
  remain unchanged.
- Progress has no Cardio, Frequency, or Muscle volume tabs; the remaining tabs
  are alphabetized; Consistency is not nested in a duplicate wrapper; Personal
  Records shows one selected exercise at a time.
- Watch permission remains visible until explicit continuation, and no initial
  WatchConnectivity/catalog reconciliation runs before that boundary.
- Swift tests, owned-warning checks, test-pyramid/network/history/Watch icon and
  platform guardrails, and a generic iOS Release build pass. No simulator or
  device is launched.

