# P8 — Rowing as a cardio box (field-test issue 8)

## Problem

> Add Rowing as another cardio box, with optional GPS, and a rowing icon from
> the same sports set we have; it should show up after Cycle.

## What the code does today

`CardioType.rowing` **already exists end-to-end**:

- Model + SF Symbol `figure.rower` — `CadenceCore/Sources/CadenceCore/Models.swift:893-927`.
- HealthKit workout type `.rowing` — `Cadence/Cadence/Services/HealthKitProvider.swift:338`
  (imported + reverse mapping at `:363`, `:378`).
- Watch already lists Rowing — `WatchRootView.swift:270`, `WatchCardioSetupView`
  (type, GPS toggle, 500 m split), `WatchWorkoutManager` activity `.rowing` (`:313`).
- Calories MET 7.0 — `CadenceCore/Sources/CadenceCore/CardioMath.swift:81`.

What is **missing** (the actual work):

1. **`WorkoutType` entry taxonomy** — `CadenceCore/Sources/CadenceCore/WorkoutType.swift:7-71`
   has no `.rowing` case. `displayName`, `symbol`, `usesGPS`, `cardioType`, and
   `WorkoutHero.colors` (`WorkoutTypePicker.swift:276-287`) all switch
   exhaustively, so adding the case forces every switch to be updated (the
   compiler will find them).
2. **The three cardio picker arrays** omit rowing or place it last:
   - `SelectWorkoutView.cardioTypes` (`WorkoutTypePicker.swift:76`):
     `[.run, .walk, .cycle, .swim, .hiit, .boxing]` — the "Start Workout" cardio
     grid the user means.
   - `RecordCardioView.types` (`RecordCardioView.swift:29`):
     `[.run, .cycle, .walk, .boxing, .hiit, .rowing]` — rowing is last, user wants it after Cycle.
   - `LogWorkoutPicker.types` (`CardioLogViews.swift:48`):
     `[.run, .walk, .cycle, .swim, .hiit, .boxing]`.
3. **HealthKit distance type** — `HealthKitProvider.distanceType(for:)`
   (`HealthKitProvider.swift:344-351`) has no `.rowing` case → falls through to
   `.distanceWalkingRunning`. iOS 16+ provides `.distanceRowing` (the watch
   already reads it — `WatchWorkoutManagerHealthKit.swift:48`).
4. **Routing** — `HomeView.start(_:)` (`HomeView.swift:760-771`) routes
   `usesGPS` types through `startOutdoorWithGoal(c)` (OutdoorCardioView with GPS +
   optional distance goal), others through `.timer`. "Optional GPS" needs a
   decision (see below).

## Design

### `WorkoutType` gains `.rowing`

Add `case rowing` to `WorkoutType` (`WorkoutType.swift:7-71`), positioned after
`cycle` (so `allCases` order reads run/walk/cycle/rowing/…):

```swift
case rowing
// displayName: "Rowing"
// symbol: "figure.rower"              (same sports-set figure family)
// usesGPS: true                        (per decision D1 — see below)
// cardioType: .rowing
// WorkoutHero.colors(.rowing): [.purple, .indigo]  (distinct from cycle's orange/yellow)
```

Add `.rowing` to `WorkoutHero.colors` (`WorkoutTypePicker.swift:276-287`) and
audit every exhaustive `switch type`/`switch self` over `WorkoutType` (the
compiler enforces it — grep `switch.*WorkoutType`, `switch self` inside
`WorkoutType`, and any `case .boxing` neighbours in the app + watch targets).

### Insert Rowing after Cycle in the three picker arrays

- `SelectWorkoutView.cardioTypes` (`WorkoutTypePicker.swift:76`) →
  `[.run, .walk, .cycle, .rowing, .swim, .hiit, .boxing]`.
- `RecordCardioView.types` (`RecordCardioView.swift:29`) →
  `[.run, .cycle, .rowing, .walk, .boxing, .hiit]`.
- `LogWorkoutPicker.types` (`CardioLogViews.swift:48`) →
  `[.run, .walk, .cycle, .rowing, .swim, .hiit, .boxing]`.

### HealthKit distance for rowing

`distanceType(for:)` (`HealthKitProvider.swift:344-351`): add
`case .rowing: return .distanceRowing`. To make this headless-testable, first
extract the mapping to a semantic enum in CadenceCore:

```swift
// CardioType extension (CadenceCore)
public enum CardioDistanceKind: Equatable, Sendable {
    case walkingRunning, cycling, swimming, rowing
}
public var distanceKind: CardioDistanceKind {
    switch self {
    case .run, .walk: .walkingRunning
    case .cycle: .cycling
    case .swim: .swimming
    case .rowing: .rowing
    case .boxing, .hiit, .other: .walkingRunning   // no dedicated distance type
    }
}
```

`HealthKitProvider.distanceType` maps `distanceKind` → `HKQuantityTypeIdentifier`
(rowing → `.distanceRowing`, guarded by `if #available(iOS 16, *)` fallback
`.distanceWalkingRunning`).

### "Optional GPS" — decision D1

Two options, recommended = **treat rowing like Cycle**:

- **Option A (recommended): `usesGPS = true`**, so the grid routes Rowing
  through the same `startOutdoorWithGoal` flow as Cycle (`HomeView.swift:765-768`)
  → OutdoorCardioView with the GPS route/map + optional distance goal. "Optional"
  is satisfied because (a) the distance goal chooser (`CardioGoalSheet`) is
  optional, (b) GPS requires location authorization and the recorder tolerates
  no fixes, and (c) the Manual Log (`LogCardioView`) lets the user log Rowing
  with no GPS at all. Zero new routing code.
- **Option B: a GPS toggle** — add a small `RowingSetupSheet` (like
  `TimerCardioSetupView`) with a GPS switch, routing `.outdoor(.rowing)` or
  `.timer(.rowing)`. More faithful to "optional GPS" at the cost of a new view
  + route branch.

The plan ships Option A unless the user picks B in `decisions.md`.

### Out of scope

Coach aerobic prescription candidates for rowing (`CoachSession.swift:166-281`)
are **not** added — the user asked for the cardio box, not a coach
recommendation. Note as future work.

## Data-model deltas

None persisted. `WorkoutType` is `Codable`/`CaseIterable`; adding `.rowing`
changes `allCases` (affects any exhaustive `ForEach(WorkoutType.allCases)` — the
full-grid `WorkoutTypePicker` at `WorkoutTypePicker.swift:11`). Check that
surface renders sanely with one more tile.

## Implementation steps

1. `WorkoutType.swift`: add `.rowing` + all members.
2. Compiler-driven sweep: fix every exhaustive switch (app + watch) — expect
   `WorkoutTypePicker.swift` (`WorkoutHero` + `colors`), `HomeView.swift`
   (`start(_:)` branches are if/else, `kindName`), `WeightsStartView`/watch
   surfaces as the compiler reports.
3. Add `CardioType.distanceKind` (CadenceCore) + `HealthKitProvider.distanceType`
   rewire.
4. Update the three picker arrays.
5. `swift test` + build (app + watch).

## Testing

### Unit tests (CadenceCoreTests — new `WorkoutTypeTests`, plus `CardioTypeTests` additions)

- `testRowingWorkoutTypePresent` — `WorkoutType.allCases.contains(.rowing)`.
- `testRowingDisplayNameAndSymbol` — "Rowing", `figure.rower`.
- `testRowingUsesGPS` — per decision D1 (Option A → `true`).
- `testRowingMapsToCardioType` — `.rowing` → `.rowing`.
- `testRowingIsNotStrength`.
- `testCardioDistanceKindRowing` — `CardioType.rowing.distanceKind == .rowing`.
- `testCardioDistanceKindExistingTypes` — run→walkingRunning, cycle→cycling,
  swim→swimming, boxing→walkingRunning (regression guard).
- `CardioTypeTests`: `testRowingSymbolIsFigureRower`, `testRowingDisplayName`
  (the model-level facts the boxes rely on).

### iPhone smoke test — one focused addition

At the point the smoke test is already on the Start Workout sheet
(`SmokeLaunchTests.swift:96-114`, after the strength-height assertions):

```swift
let rowing = app.buttons["startType.rowing"]
XCTAssertTrue(rowing.waitForExistence(timeout: 5), "Start Workout did not offer Rowing")
let cycle = app.buttons["startType.cycle"]
XCTAssertTrue(cycle.exists, "Start Workout lost Cycle")
XCTAssertGreaterThan(rowing.frame.minY, cycle.frame.minY,
                     "Rowing is not after Cycle in the cardio grid")
```

The grid elements exist in the accessibility tree even if below the fold, so
frame comparison is reliable. Cost: ~3–5 s. This proves "after Cycle" end-to-end
and that `.rowing` surfaced in the entry taxonomy. (Optionally also assert
`startType.rowing` is below `startType.cycle` and above `startType.swim`.)

### Watch smoke — unchanged. Rowing already exists on the watch.

## Open questions

- D1 (GPS treatment): Option A vs Option B — see `decisions.md`.
- Whether to add a `hero-rowing` image asset for the hero tile. The existing
  heroes load `hero-<rawValue>` images if present; without an asset the gradient
  + SF Symbol renders (the `.other` tile already works that way). Ship without a
  new asset; note it as a polish follow-up.
