# Phase 4 — View-only exercise detail in the workout summary, with partner rows

Field-test issue #1: *"when on strength workout summary/history, I should be able
to expand/collapse the exercise to see details 'view only' WITHOUT having to edit
the workout first, furthermore if there are multiple partners then the detail of
the exercise should look like this: one row per partner, 'Me' first, in this
abbreviated format: 180lb x 12, 190lb x 10, 200lb x 8"*

## 1. What the code does today

`Cadence/Cadence/Features/Workout/WorkoutSummaryView.swift`:
- `strengthSection` lists `data.exercises` as `exerciseRow(...)`.
- Each row's title is a `Button` that calls `onExercise(sourceID)`, which Home
  (`HomeView.swift:243`) and Progress (`ProgressView.swift:49`) route to
  `HistorySummaryRoute.strengthFocused` → **`SessionView` (the editor)**.
  So: no detail without entering edit.
- A separate `partnersSection` renders each partner's exercises at the bottom.
- `WorkoutSummaryData.ExerciseLine` carries `setCount`, `topSetWeightKg`,
  `reps: [Int]` — **no per-set weights**, so an abbreviated
  `180 lb x 12, 190 lb x 10, 200 lb x 8` line is not currently expressible.

## 2. Data model change — `CadenceCore/Sources/CadenceCore/WorkoutSummaryData.swift`

Additive, value-type only, no schema/persistence change.

```swift
/// One logged working set, in logged order.
public struct SetLine: Equatable, Sendable {
    /// Canonical kg. For a bodyweight set this is the *added* load (0 = pure BW).
    public let weightKg: Double
    public let reps: Int
    public let usesBodyweight: Bool
    public init(weightKg: Double, reps: Int, usesBodyweight: Bool)
}

/// One performer's working sets for an exercise. `isMe == true` sorts first and
/// is labelled "Me"; partners follow in first-appearance order.
public struct PerformerLine: Equatable, Sendable, Identifiable {
    public let name: String          // "Me" or the partner's name
    public let isMe: Bool
    public let sets: [SetLine]
    public var id: String { name }
    public init(name: String, isMe: Bool, sets: [SetLine])
}
```

`ExerciseLine` gains **one** new stored property (defaulted in `init` so every
existing construction keeps compiling):

```swift
public let performers: [PerformerLine]
```

`from(session:)` builds it per exercise:
1. owner working sets → `PerformerLine(name: "Me", isMe: true, …)` — **always
   first**, and included even when empty only if the owner has ≥1 set for the
   exercise;
2. then each partner with ≥1 working set for that exercise, in first-appearance
   order across `session.orderedSets`.

Reuse the existing `lines(in:belongs:)` helper's filtering predicates so owner /
partner attribution stays identical to `WorkoutSession.totalVolume`'s rule
(`isOwnerSet`, warmups excluded).

`ExerciseLine.reps` and `topSetWeightKg` stay (other callers use them).

## 3. Presenter — `CadenceCore/Sources/CadenceFeatures/WorkoutSummaryPresenter.swift`

```swift
/// "180 lb x 12" — a single logged set. Bodyweight renders "BW x 12", a weighted
/// bodyweight variant "BW + 10 lb x 12". Decision D8: lowercase `x`.
public static func setLine(_ set: WorkoutSummaryData.SetLine,
                           unit: MeasurementUnitPreference) -> String

/// "180 lb x 12, 190 lb x 10, 200 lb x 8" — one performer's whole exercise.
public static func performerSetsText(_ performer: WorkoutSummaryData.PerformerLine,
                                     unit: MeasurementUnitPreference) -> String

/// The performers to show, "Me" first, then partners in the order given.
/// Drops performers with no working sets.
public static func orderedPerformers(_ line: WorkoutSummaryData.ExerciseLine)
    -> [WorkoutSummaryData.PerformerLine]

/// VoiceOver value for an expanded exercise, e.g.
/// "Me: 180 pounds by 12, 190 pounds by 10. Alex: 140 pounds by 12."
public static func expandedAccessibilityValue(_ line: WorkoutSummaryData.ExerciseLine,
                                              unit: MeasurementUnitPreference) -> String
```

All pure. Formatting uses `Format.weight(_:unit:decimals: 0)`.

## 4. View

### Layout

```
Exercises
┌─────────────────────────────────────────────┐
│ Standing Dumbbell Upright Row      45 lb  ⌄ │  ← tap anywhere toggles
│ 3 sets · reps 12, 10, 8                     │
└─────────────────────────────────────────────┘

expanded:
┌─────────────────────────────────────────────┐
│ Standing Dumbbell Upright Row      45 lb  ⌃ │
│ 3 sets · reps 12, 10, 8                     │
│ ─────────────────────────────────────────── │
│ Me      180 lb x 12, 190 lb x 10, 200 lb x 8│
│ Alex    140 lb x 12, 145 lb x 10, 150 lb x 8│
└─────────────────────────────────────────────┘
```

Solo workouts show a single `Me` row (keep the label — it is unambiguous and
avoids a second code path).

### New file — `Cadence/Cadence/Features/Workout/WorkoutSummaryExerciseRow.swift`

`WorkoutSummaryView.swift` is 339 LOC; the new row plus the expansion state would
push it past 400. Extract:

```swift
struct WorkoutSummaryExerciseRow: View {
    let line: WorkoutSummaryData.ExerciseLine
    let unit: MeasurementUnitPreference
    let isExpanded: Bool
    let idPrefix: String
    let onToggle: () -> Void
}
```
Requirements:
- The whole card is one `Button(action: onToggle)` with `.buttonStyle(.plain)`
  **and `.contentShape(Rectangle())`** — the card is an `HStack` with a `Spacer`,
  and without `contentShape` the gap is not tappable (known repo gotcha).
- `.accessibilityElement(children: .contain)` on the card **before** its
  `.accessibilityIdentifier`, otherwise the styled card collapses its children
  and the per-performer ids disappear from the tree (known repo gotcha).
- Identifiers:
  - card: `summary.exercise.<sourceExerciseID or name>` (**unchanged** from today
    so `ProgressPresenterTests`/smoke keep resolving),
  - chevron state exposed via `.accessibilityValue(isExpanded ? "Expanded" : "Collapsed")`,
  - each performer row: `summary.exercise.<key>.performer.<name>`.
- Dynamic Type: no fixed heights; `minHeight: 44` on the tappable card.

### `WorkoutSummaryView.swift` changes
- `@State private var expandedExerciseIDs: Set<String> = []`.
- `strengthSection` renders `WorkoutSummaryExerciseRow` and toggles the set.
- Replace the hint text with
  `"Tap an exercise to see every set. Use Edit to change them."`
- **Delete `partnersSection`** and its call site (decision **D6**).
- `onExercise` closure: **remove the parameter entirely** from
  `WorkoutSummaryView` and delete its two call sites' `onExercise:` arguments in
  `Home/HomeView.swift:243` and `Progress/ProgressView.swift:49`.
  Keep `HistorySummaryRoute.strengthFocused` and its `navigationDestination`
  (Progress's exercise-trend route still uses it) — only the summary stops
  originating it.
- Keep the `Edit` toolbar button (`summary.edit`) exactly as-is: it is the escape
  hatch to editing (NFR-8, decision **D7**).

## 5. Tests

### `CadenceCore/Tests/CadenceCoreTests/WorkoutSummaryDataTests.swift` (extend)
```
testExerciseLinePutsMeFirst
testExerciseLineIncludesEachPartnerOnce
testPartnersAppearInFirstAppearanceOrder
testPerformerSetsAreInLoggedOrder
testWarmupSetsAreExcludedFromPerformerLines
testSoloSessionHasOneOwnerPerformerLine
testBodyweightSetCarriesUsesBodyweightAndAddedLoad
testExerciseWithOnlyPartnerSetsIsStillExcludedFromOwnerLines  // existing rule
```

### `CadenceCore/Tests/CadenceFeaturesTests/WorkoutSummaryPresenterTests.swift` (extend)
```
testSetLineUsesPoundsWhenPreferred            // "180 lb x 12"
testSetLineUsesKilogramsWhenPreferred
testSetLineRendersBodyweight                  // "BW x 12"
testSetLineRendersWeightedBodyweight          // "BW + 10 lb x 12"
testPerformerSetsTextJoinsWithCommaSpace      // "180 lb x 12, 190 lb x 10, 200 lb x 8"
testOrderedPerformersPutsMeFirst
testOrderedPerformersDropsEmptyPerformers
testExpandedAccessibilityValueNamesEachPerformer
```

### UI smoke — inside the single existing test
After the post-workout summary renders and **before** tapping `summary.done`:
```swift
// Field test 2026-08-18 #1: the summary expands an exercise read-only.
if app.descendants(matching: .any)["summary.exercise"].firstMatch.exists {
    let row = app.descendants(matching: .any)
        .matching(NSPredicate(format: "identifier BEGINSWITH 'summary.exercise'")).firstMatch
    row.tap()
    XCTAssertFalse(app.buttons["session.addExercise"].exists,
                   "Expanding a summary exercise navigated into the editor")
}
```
Assert only that expanding does **not** leave the summary — that is the
regression the user reported.

## 6. Acceptance criteria

- [ ] Tapping an exercise in a strength summary (post-workout, Home This Week,
      Progress full history) expands an inline read-only detail; it never pushes
      the editor.
- [ ] The detail shows one row per performer, `Me` first, then partners.
- [ ] Each row reads `180 lb x 12, 190 lb x 10, 200 lb x 8` (unit follows
      `settings.unit`; bodyweight renders `BW x 12`).
- [ ] Collapsing restores the compact row; state is per-exercise, multiple rows
      can be open at once.
- [ ] The bottom `Partners` section is gone (its data now lives in the rows).
- [ ] `Edit` in the toolbar still opens `SessionView`.
- [ ] VoiceOver reads the exercise name, the summary line, expansion state, and
      each performer's sets.
- [ ] `WorkoutSummaryView.swift` and `WorkoutSummaryExerciseRow.swift` each ≤ 400 LOC.
- [ ] `make ci` green; `make smoke` green.

## 7. Commit

```
feat: read-only exercise detail in workout summaries, one row per performer

Field test 2026-08-18 #1. Summaries expand an exercise in place — Me first, then
each partner, as "180 lb x 12, 190 lb x 10, 200 lb x 8" — instead of requiring
Edit. The separate Partners roll-up is folded into those rows.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

Update `current_status.md`, commit, **do not push**, report, stop.
