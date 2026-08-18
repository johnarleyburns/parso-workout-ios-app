# Phase 2 — Home's vertical rhythm on Workout Plan, Start Workout and Workout

Field-test issue #5: *"On Workout Plan View and Start Workout View and Workout
View, I want the EXACT SAME vertical space between all buttons and text boxes as
I have on the homeview, currently it's a hodgepodge of different layouts."*

Depends on **Phase 1** (`LayoutMetrics`).

## 1. Home's rhythm (the reference)

`Home/HomeView.swift:200-223`:

```
ScrollView {
  VStack(alignment: .leading, spacing: 20) {   ← sectionSpacing
      headerDate
      resumeCard?
      homeActionRow                            ← internal spacing 12 (P1)
      workoutsTodaySection    ┐
      HomeWeekDashboardSection├ each: .padding(16) + cadenceGlassCard(corner 16)
      coachSuggestionsSection ┘   inner VStack spacing 10…12
  }
  .padding()                                   ← pagePadding 16
}
```

So: **20** between sections, **16** page padding, **16** card padding,
**12** between rows in a card, **10** between a card heading and its first row.
These are exactly `LayoutMetrics.sectionSpacing / pagePadding / cardPadding /
cardRowSpacing / cardHeadingSpacing`.

## 2. What each target surface does today

### 2a. Workout Plan — `Home/WorkoutPlanEditor.swift` (399 LOC — at the cap)
```
VStack(spacing: 0) {
    startButton          // padding(.horizontal,16) + padding(.vertical,8)
    List { … }           // system-inset grouped rows; spacing owned by List
}
```
A `List` cannot honour a 20 pt section rhythm — it applies its own row insets and
section spacing. Per decision **D14** it is converted to a `ScrollView` + `VStack`
of glass cards.

### 2b. Start Workout — `Home/WorkoutTypePicker.swift` `SelectWorkoutView`
```
VStack(alignment: .leading, spacing: 22) {   // 22, not 20
    VStack(spacing: 10) { "Strength" + 3 actions + a link }   // 10, not 12
    VStack(spacing: 10) { "Cardio" + LazyVGrid(spacing: 16) }
}
.padding()
```

### 2c. Workout — `Train/SessionView.swift:277-348`
```
VStack(alignment: .leading, spacing: 16) { … }   // 16, not 20
.padding()
```
plus ad-hoc `.padding(.top, 16 / 8 / 4)` on individual children.

## 3. Design

### Workout Plan (rewritten skeleton)

```
┌──────────────────────────────────────────────┐
│ ▶  Start Workout                             │  56 pt, full width
└──────────────────────────────────────────────┘
                   ↕ 20
┌─ Training partners ──────────────────────────┐
│ Solo workout                                 │  card, padding 16, corner 16
└──────────────────────────────────────────────┘
                   ↕ 20
┌─ Bench Press ────────────────────────────────┐
│ 80 kg×8  ·  85 kg×6  ·  90 kg×5              │
└──────────────────────────────────────────────┘
                   ↕ 20
┌─ … each exercise is its own card … ──────────┐
                   ↕ 20
┌──────────────────────────────────────────────┐
│ ＋ Add Exercise            (edit mode)       │
│ ⚙︎ Show workout settings…  (view mode)       │
└──────────────────────────────────────────────┘
```

Implementation notes:
- `ScrollView { VStack(alignment: .leading, spacing: sectionSpacing) { … } .padding(pagePadding) }`.
- The `Start Workout` button becomes a `safeAreaInset(edge: .top)` **or** the
  first child of the VStack — keep it the first child (simplest, and the smoke
  test taps `editor.start` without scrolling because it is at the top).
- Every former `Section` becomes a `VStack(alignment: .leading, spacing: cardRowSpacing)`
  with `.padding(cardPadding)` + `.frame(maxWidth: .infinity, alignment: .leading)`
  + `.cadenceGlassCard(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: .green)`.
- Section headers become a `Text(...).font(.headline)` first child, followed by
  `cardHeadingSpacing`. Use a small `planCard(_ title:content:)` helper.
- `ForEach(exercise.sets)` `.onDelete` no longer works outside a `List` — replace
  per-set deletion with a trailing `Button(role: .destructive)` `minus.circle`
  per set row in edit mode, id `editor.removeSet.<exerciseName>.<index>`.
- The reorder `Image(systemName: "line.3.horizontal")` handle currently does
  nothing (no `.onMove`); leave it out of the rewrite rather than shipping a dead
  affordance.

**LOC control:** `WorkoutPlanEditor.swift` is at 399. Split before editing:
- `Home/WorkoutPlanEditor.swift` — the view shell, start button, sheets, toolbar.
- **New** `Home/WorkoutPlanPartnerSection.swift` — `partnerSummarySection`,
  `partnerEditorSections`, the roster helpers (`editorRoster`,
  `explicitPartnerIDs`, `normalizedPartnerIDs`, `moveRosterMember`).
- **New** `Home/WorkoutPlanExerciseSection.swift` — `exerciseSection`, `setRow`,
  `applyPickedExercise`, `removeExercise`, and the read-only `CompactExerciseRow`
  wrapper.
Each new file must stay ≤ 400 LOC.

### Start Workout
- Outer `VStack` spacing `22 → sectionSpacing (20)`.
- Group `VStack` spacing `10 → cardRowSpacing (12)`.
- `LazyVGrid(spacing: 16)` and its column spacing `16` stay (a grid gutter is not
  a section gap).
- `.padding()` → `.padding(pagePadding)`.
- Wrap the "Strength" and "Cardio" groups in the same glass card treatment as
  Home's sections so the two screens read identically.

### Workout (SessionView)
- Outer `VStack` spacing `16 → sectionSpacing (20)`.
- `.padding()` → `.padding(pagePadding)`.
- Delete the ad-hoc `.padding(.top, 16)`, `.padding(.top, 8)`, `.padding(.top, 4)`
  on `ContentUnavailableView`, `session.addExercise`, `WorkoutControlBar` and
  `log.done` — the uniform 20 pt spacing replaces them.
- Leave the `safeAreaInset(edge: .top)` header alone.
- **SessionView ≤ 1102 LOC**: this edit removes lines. If it does not, extract
  `plannedCard` + `partnerBar` into `Train/SessionViewShared.swift` (62 LOC, room
  to spare).

## 4. Tests

### New — `CadenceCore/Tests/CadenceFeaturesTests/LayoutMetricsTests.swift` (extend)
```
testWorkoutSurfacesShareHomeSectionSpacing   // documents that all three use sectionSpacing
```
Real enforcement is the grep in acceptance criteria + the smoke test; the metric
test guards the constant.

### UI smoke — inside the single existing test
After opening the plan editor via `selectWorkout.custom`, assert the editor is a
scroll surface with the new card ids present:
```swift
XCTAssertTrue(app.descendants(matching: .any)["editor.partners"].waitForExistence(timeout: 5),
              "Workout Plan lost its Training partners card")
XCTAssertTrue(app.buttons["editor.addExercise"].exists,
              "Custom Workout did not open in edit mode")
```
(`editor.partners` is a new identifier on the partners card; `editor.addExercise`
already exists and must keep working after the List→ScrollView conversion.)

### Existing tests to re-check
- `EditablePlanTests` — unaffected (pure model).
- `SmokeLaunchTests` navigation via `editor.start` / `editor.addExercise` /
  `editor.showSettings` — all three ids must survive the rewrite.

## 5. Acceptance criteria

- [ ] `WorkoutPlanEditor` renders a `ScrollView`, not a `List`, with
      `spacing: LayoutMetrics.sectionSpacing` and `padding(LayoutMetrics.pagePadding)`.
- [ ] `SelectWorkoutView` and `SessionView` use `sectionSpacing` / `pagePadding`
      from `LayoutMetrics` — no literal `spacing: 16` / `spacing: 22` at the
      top-level VStack of either.
- [ ] No `.padding(.top, N)` remains on the direct children of `SessionView`'s
      top-level VStack.
- [ ] Sets can still be deleted in the plan editor (new destructive button) and
      partners can still be selected/reordered.
- [ ] `editor.start`, `editor.addExercise`, `editor.showSettings`,
      `editor.partner.<name>`, `editor.newPartnerName`, `editor.addPartner`,
      `editor.partnerOrder.up.<name>`, `editor.partnerOrder.down.<name>`,
      `editor.exerciseMenu.<name>`, `editor.swapExercise.<name>`,
      `editor.addSet.<name>`, `editor.compactExercise.<name>` all still resolve.
- [ ] `WorkoutPlanEditor.swift`, `WorkoutPlanPartnerSection.swift`,
      `WorkoutPlanExerciseSection.swift` each ≤ 400 LOC.
- [ ] `make ci` green; `make smoke` green.

## 6. Commit

```
refactor: give Workout Plan, Start Workout and Workout Home's vertical rhythm

Field test 2026-08-18 #5. Workout Plan moves off List so it can honour the
20/16/12 section rhythm; all three surfaces read their spacing from LayoutMetrics.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

Update `current_status.md`, commit, **do not push**, report, stop.
