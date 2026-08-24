# Phase 5 — Home "This Week": Volume becomes muscle-group volume

**Depends on:** Phase 4. **UI impact:** yes. **`make smoke` required.**

## Problem

`This Week` shows two rows that measure the same thing at two resolutions —
`Volume` (8 `BodyPart` buckets) and `Muscles` (21 `MuscleCatalog` entries) — and
the expanded card repeats both lists. The fine list is the useful one; the coarse
one is the redundant simplification the request removes.

## What the code does today

- `HomeDashboardPresenter.make(...)` builds `volume: [VolumeRow]` (keyed by
  `BodyPart`), `volumeCoverage: Progress`, `muscles: [MuscleRow]` (keyed by
  `MuscleCatalog` id) and `muscleCoverage: Progress`.
- `HomeWeekDashboardSection` renders four progress rows (Strength, Cardio,
  Volume, Muscles) plus, when expanded: workout groups → cardio minutes →
  a `Volume` heading + `volumeRow` list → total volume → a `Muscles` heading +
  `muscleRow` list.
- Identifiers in use: `home.week.volume`, `home.week.muscles`,
  `home.week.volumeHeading`, `home.week.musclesHeading`,
  `home.volume.<bodyPart.rawValue>`, `home.muscle.<muscleID>`,
  `home.volume.total`, `home.thisWeek.expanded`.
- `Cadence/CadenceUITests/SmokeLaunchTests.swift` asserts `home.volume.legs`
  (lines 53–55), `home.week.muscles` (62, 68) and `home.muscle.chest` (64).

## Design

One dimension, one row, one list.

### `HomeDashboardState` (`CadenceFeatures/HomeDashboardPresenter.swift`)

- **Delete** `MuscleRow`, `muscles`, `muscleCoverage`.
- **Replace** `VolumeRow` with:
  ```swift
  public struct VolumeRow: Sendable, Equatable, Identifiable {
      public let group: MuscleGroup
      public let displayName: String        // group.displayName
      public let scientificName: String     // group.scientificName
      public let sets: Double
      public let zone: WeeklySetZone
      public let rangeText: String
      public let normalized: Double         // WeeklySetProgress.normalized(sets)
      /// False for a group the user does not track — shown because it has volume,
      /// not because the coach targets it (decision D4).
      public let isTracked: Bool
      public let citationID: String
      public var id: MuscleGroup { group }
  }
  ```
- `volume` rows = every tracked group **plus** every untracked group with
  `sets > 0`, sorted by `displayName` (`localizedCaseInsensitiveCompare`, tie-break
  on `rawValue`) — matching the alphabetical convention settled 2026-08-22.
- `volumeCoverage` keeps its meaning ("avg sets" against the 12-set scale) but
  averages **tracked** rows only, so an incidental 0.5 sets of `neck` cannot drag
  the headline number down.
- `displayName(for:)` (the old `Muscle`-based helper) is deleted;
  `MuscleGroup.displayName` replaces it.
- Signature: `make(snapshot:schedule:goal:experience:userAge:)` reads
  `schedule.trackedMuscleGroups` for `isTracked`, and
  `snapshot.facts.weeklySetsByGroup` for the numbers.

### `HomeWeekDashboardSection` (`Cadence/Cadence/Features/Home/`)

- Delete the `home.week.muscles` progress row (lines ~30–33).
- Delete the entire `muscles` / `muscleRow(_:)` section (lines ~156–200) and the
  `Divider().padding(.top, 2)` that precedes it.
- Keep the `Volume` progress row; add `caption: weeklySetCaption` (it already has
  it) — unchanged.
- In `expandedWeek`, the `Volume` heading now introduces the muscle-group list.
  Render with the old `muscleRow` layout (name column 116pt, progress bar,
  trailing sets + range text) since it is the richer of the two, renamed
  `volumeRow(_:)`; keep the `Above 12-set maximum` warning label from the current
  `volumeRow`.
- Untracked rows render their name with `.secondary` foreground and an
  `Image(systemName: "circle.dashed")` prefix plus accessibility hint
  `"Not a tracked muscle group"`. No other visual difference.
- Identifiers after this phase:
  - `home.week.volume` — the collapsed progress row (unchanged id)
  - `home.week.volumeHeading` — unchanged
  - `home.volume.<group.rawValue>` — e.g. `home.volume.quadriceps`,
    `home.volume.lower_back`
  - `home.volume.total` — unchanged
  - `home.week.muscles`, `home.week.musclesHeading`, `home.muscle.*` — **gone**
- The citation under the list keeps `iversenTimeEfficient2021` and its context
  string becomes: `"Weekly set volume is shown on a shared 4-to-12-set scale for
  each muscle group."` Add a second `CitationLink` for
  `pellandDoseResponse2026` with context `"Direct sets count once and indirect
  sets count half."` — that claim is now on screen and must cite (HARD RULE).

### Other consumers of the deleted state

`grep -rn "muscleCoverage\|\.muscles\b\|MuscleRow" Cadence CadenceCore` and fix:
- `HomeView+Dashboard.swift` — passes `dashboard` wholesale; check for any direct
  `muscles` reference.
- `HomeDashboardPresenterTests` — rewrite for the new shape.

### `WeekVolumePresenter` (Your Plan screen)

Re-key `PartRow` → `GroupRow` on `MuscleGroup`, reading
`PlanAwareWeeklyAccounting.completedSetsByGroup` /
`plannedRemainingSetsByGroup` and `VolumeLandmarks.bands(for: group,)`. The
`excluded:` parameter becomes `tracked: Set<MuscleGroup>` (rows shown = tracked ∪
{group : done+planned > 0}). Update `VolumeLandmarkBar.swift` and `ProgressView`
call sites to match — both currently take `BodyPart`.

## Smoke test (`SmokeLaunchTests.swift`)

Within the single existing test function:
- line 53: `home.volume.legs` → `home.volume.quadriceps`
- lines 62–68: replace the `home.week.muscles` / `home.muscle.chest`
  assertions with:
  - `home.week.volumeHeading` exists after expansion
  - `home.volume.chest` exists
  - `home.volume.quadriceps` exists
  - `XCTAssertFalse(app.descendants(matching: .any)["home.week.muscles"].exists)`
    — a positive assertion that the redundant section is gone
- Do **not** add a test function (pyramid guardrail).

## Tests — `CadenceFeaturesTests/HomeDashboardPresenterTests.swift`

- `testVolumeRowsCoverEveryTrackedGroup`
- `testUntrackedGroupIsHiddenWhenZeroAndShownWhenTrained`
- `testVolumeRowsAreAlphabeticalByDisplayName`
- `testVolumeCoverageAveragesTrackedRowsOnly`
- `testZoneMappingUnchanged` — 0 → belowMinimum, 4 → building, 8 → productive,
  12 → productive, 12.5 → aboveMaximum
- `testDisplayNamesAreTitleCased` — `lower_back` → `Lower Back`
- `testNoMuscleRowsRemain` — the state type no longer exposes `muscles`
  (compile-level, but assert `volume` is the only per-muscle list)

## Verification

```
make ci && make smoke
```

If the simulator behaves badly (`no debugger version`, ~45s launches), restart
CoreSimulator (`killall -9 com.apple.CoreSimulator.CoreSimulatorService`) and
re-run; report honestly which failures are environmental.

## Acceptance criteria

- [ ] `This Week` has three progress rows: Strength, Cardio, Volume.
- [ ] The expanded card has exactly one per-muscle list, under `Volume`.
- [ ] Rows are `MuscleGroup`-keyed, alphabetical, tracked-first-then-trained.
- [ ] Both on-screen volume claims cite through `CitationRegistry` +
      `CitationLink`.
- [ ] `home.muscle.*` and `home.week.muscles` identifiers no longer exist.
- [ ] Your Plan / Progress volume surfaces are on `MuscleGroup` too.
- [ ] `make ci` and `make smoke` green.
- [ ] `scripts/check-test-pyramid.sh` ratchets for `HomeWeekDashboardSection.swift`
      updated **downward** (the file shrinks by ~45 lines).

## Commit

`feat: show weekly volume per muscle group on home`
