# Phase 1 — Uniform full-width action buttons

Field-test issue #3: *"ensure HomeView, Workout Plan view, and Start Workout view
all have the same height full-width buttons: currently Quick Start, Custom
Workout, Coach's Workout, Start Workout, all have varying heights."*

## 1. What the code does today

| Control | File | Metrics today |
|---|---|---|
| Home `Start Workout` | `Home/HomeView.swift:566-585` (`homeActionRow`) | `.borderedProminent`, `.green`, `.font(.headline)`, `minHeight: 52` |
| Home `Log Previous Workout` | same | `.bordered`, `.font(.headline)`, `minHeight: 52` |
| Start Workout sheet `Quick Start` / `Custom Workout` / `Coach's Workout` | `Home/WorkoutTypePicker.swift` (`SelectWorkoutView.workoutChoiceLabel`) | gradient card, `.font(.title3.bold())`, `padding(.vertical, 16)`, `minHeight: 64`, corner 18 |
| Strength start `Coach's Workout` | `Home/WeightsStartView.swift:20-50` | glass card, `padding(.vertical, 14)`, `minHeight: 60`, corner 18 |
| Strength start `Quick Start` | `Home/WeightsStartView.swift:55-80` | glass card, `padding(.vertical, 16)`, `minHeight: 60`, corner 18 |
| Workout Plan `Start Workout` | `Home/WorkoutPlanEditor.swift:131-144` (`startButton`) | `.borderedProminent`, `.green`, `.controlSize(.large)`, `.font(.title3.bold())`, `minHeight: 56` |
| `Do Coach's Workout` | `Home/HomeCoachRecommendationCard.swift:30-36` | `.borderedProminent`, `.green`, **no minHeight at all** |

Five different heights (52 / 56 / 60 / 64 / intrinsic) and four different fonts.

## 2. Design

One canonical control, one source of truth for its numbers (decisions **D2**,
**D3**).

```
┌────────────────────────────────────────────────┐
│  ▶  Start Workout                              │   56 pt tall, full width,
└────────────────────────────────────────────────┘   .headline, corner 16
                    ↕ 12 pt
┌────────────────────────────────────────────────┐
│  ✎  Log Previous Workout                       │   56 pt tall, full width
└────────────────────────────────────────────────┘
```

- Height **56 pt** for every primary full-width action (the midpoint of today's
  spread; ≥44 pt HIG target, and it is what the plan editor already uses).
- Font `.headline` everywhere (the `.title3.bold()` variants get smaller — this
  is intentional, it is Home that sets the standard).
- Corner radius 16, matching the glass cards.
- The label is `Label(title, systemImage:)`, leading-aligned content centred
  horizontally, so icons line up between screens.

## 3. New: `CadenceCore/Sources/CadenceFeatures/LayoutMetrics.swift`

Pure, `Double`-valued, no SwiftUI (guard rule). Every number the UI phases need
lives here so the "same height / same spacing" claims are unit-tested.

```swift
import Foundation

/// Single source of truth for Cladiron's shared layout rhythm. Kept in
/// CadenceFeatures (Foundation only) so "these controls are the same height" and
/// "these surfaces share Home's spacing" are unit-tested facts, not visual
/// claims. The app maps these Doubles to CGFloat at the call site.
public enum LayoutMetrics {
    // MARK: Full-width actions
    /// Height of every primary full-width action button (Home Start Workout,
    /// Quick Start, Custom Workout, Coach's Workout, plan-editor Start Workout,
    /// Do Coach's Workout).
    public static let actionButtonHeight: Double = 56
    /// Corner radius of a full-width action button.
    public static let actionButtonCornerRadius: Double = 16
    /// Vertical gap between two stacked full-width actions.
    public static let actionButtonSpacing: Double = 12

    // MARK: Page rhythm (Home is the reference)
    /// Gap between top-level sections on a scrolling surface.
    public static let sectionSpacing: Double = 20
    /// Outer page padding.
    public static let pagePadding: Double = 16
    /// Gap between rows inside a card.
    public static let cardRowSpacing: Double = 12
    /// Gap between a card's heading and its first row.
    public static let cardHeadingSpacing: Double = 10
    /// Inner padding of a card.
    public static let cardPadding: Double = 16
}
```

## 4. New: `Cadence/Cadence/Shared/CadenceActionButton.swift`

```swift
import SwiftUI
import CadenceFeatures

/// The one full-width action control. Every primary/secondary full-width button
/// on Home, Start Workout, Workout Plan and the live workout uses this so the
/// heights and typography cannot drift again (field test 2026-08-18 issue 3).
struct CadenceActionButton: View {
    enum Emphasis { case primary, secondary }

    let title: String
    let systemImage: String
    var emphasis: Emphasis = .primary
    var tint: Color = .green
    let action: () -> Void
    …
}

extension View {
    /// Applies the canonical full-width action geometry to a label. Use when the
    /// call site must stay a NavigationLink (which cannot be a Button).
    func cadenceActionLabel() -> some View { … }
}
```

Requirements for the implementation:
- `frame(maxWidth: .infinity, minHeight: CGFloat(LayoutMetrics.actionButtonHeight))`.
- `.font(.headline)`.
- `.primary` → `.buttonStyle(.borderedProminent).tint(tint)`;
  `.secondary` → `.buttonStyle(.bordered)`.
- Accepts and forwards an `accessibilityIdentifier` via the call site (do **not**
  bake ids in — the existing ids must be preserved verbatim).
- Dynamic Type: never set a fixed frame *height*, only `minHeight`.
- Provide `cadenceActionLabel()` for `NavigationLink` labels
  (`SelectWorkoutView`, `WeightsStartView`) which keep their gradient/glass fill
  via the existing `cadenceGlassBackground(in:tint:interactive:fallback:)` — only
  the geometry (`minHeight`, corner radius, font) comes from the modifier.

## 5. Call-site edits

| File | Change |
|---|---|
| `Home/HomeView.swift` `homeActionRow` | Replace the two inline `Button`s with `CadenceActionButton`. Keep ids `home.startWorkout`, `home.logWorkout`. VStack spacing → `LayoutMetrics.actionButtonSpacing`. **HomeView must not grow** — this edit removes lines, which is fine. |
| `Home/WorkoutTypePicker.swift` `SelectWorkoutView.workoutChoiceLabel` | Keep the gradient fill; swap the geometry to `cadenceActionLabel()` (56 pt, `.headline`, corner 16). Keep ids `selectWorkout.quickStart`, `selectWorkout.custom`, `selectWorkout.coach`. |
| `Home/WeightsStartView.swift` | Same treatment for `weights.coachStart` and `weights.quickStart`; keep their glass fills, normalize geometry. |
| `Home/WorkoutPlanEditor.swift` `startButton` | Use `CadenceActionButton`; drop `.controlSize(.large)` and `.font(.title3.bold())`. Keep id `editor.start` and the `Start Workout` label (the smoke test asserts both). |
| `Home/HomeCoachRecommendationCard.swift` | `Do Coach's Workout` becomes a `CadenceActionButton`; keep id `home.coachRecommendation.start`. |
| `Features/Train/SessionView.swift` | `Use Previous Workout`, `Add Exercise`, `Done` adopt the same geometry. Keep ids `session.usePrevious`, `session.addExercise`, `log.done`. **SessionView ≤ 1102 LOC** — this is a net-neutral/shrinking edit. |

Do **not** change `WorkoutControlBar` (Pause/End are a 2-up pair at 56 pt already
and are governed by their own doc comment).

## 6. Tests

### New — `CadenceCore/Tests/CadenceFeaturesTests/LayoutMetricsTests.swift`
```
testActionButtonHeightIsSingleSourced        // == 56, and > 44 (HIG minimum)
testActionButtonSpacingIsPositiveAndSmallerThanSectionSpacing
testSectionSpacingMatchesHomeRhythm          // == 20
testCardRhythmIsInternallyConsistent         // cardHeadingSpacing <= cardRowSpacing <= sectionSpacing
testPagePaddingIsSystemStandard              // == 16
```
These are cheap invariants; their value is that a future edit that hard-codes a
different height in a view is caught by the *next* phase's guard-rail review, and
that the numbers have exactly one home.

### Existing — no test should break.
Run `swift test --package-path CadenceCore` and confirm the count is
**1,318 + 5 = 1,323** (adjust the expectation if the baseline moved).

### UI smoke — `Cadence/CadenceUITests/SmokeLaunchTests.swift`
Add **inside the single existing test** (do not add a second `func test…`), after
the existing `selectWorkout.custom` assertions:

```swift
// Field test 2026-08-18 #3: the full-width strength actions are one height.
let quick = app.buttons["selectWorkout.quickStart"]
let custom = app.buttons["selectWorkout.custom"]
let coach = app.buttons["selectWorkout.coach"]
XCTAssertTrue(quick.waitForExistence(timeout: 5), "Start Workout lost Quick Start")
XCTAssertEqual(quick.frame.height, custom.frame.height, accuracy: 1,
               "Quick Start and Custom Workout are different heights")
if coach.exists {
    XCTAssertEqual(quick.frame.height, coach.frame.height, accuracy: 1,
                   "Coach's Workout is a different height from Quick Start")
}
```

and, after the plan editor opens:

```swift
XCTAssertEqual(app.buttons["editor.start"].frame.height, quickHeight, accuracy: 1,
               "Workout Plan Start Workout is a different height from Start Workout's actions")
```
(capture `quickHeight` before dismissing the sheet).

## 7. Acceptance criteria

- [ ] `LayoutMetrics.swift` exists in CadenceFeatures and imports **only** Foundation.
- [ ] `CadenceActionButton` exists in `Cadence/Cadence/Shared/` and is the only
      place `minHeight` for a full-width action is written.
- [ ] `grep -rn "minHeight: 5\|minHeight: 6" Cadence/Cadence/Features` returns no
      full-width primary action (the WorkoutControlBar 56 pt pair is exempt).
- [ ] Home `Start Workout`, Home `Log Previous Workout`, `Quick Start`,
      `Custom Workout`, `Coach's Workout`, plan editor `Start Workout`, and
      `Do Coach's Workout` all render at 56 pt and use `.headline`.
- [ ] All existing accessibility identifiers unchanged.
- [ ] `make ci` green; `make smoke` green.
- [ ] `scripts/check-test-pyramid.sh` reports HomeView ≤ 1115 and every other
      Features file ≤ 400 (or its ratchet). If HomeView shrank, lower its ratchet
      entry to the new LOC.

## 8. Commit

```
feat: single full-width action button geometry across Home, Start and Plan

Field test 2026-08-18 #3. LayoutMetrics (CadenceFeatures) is the single source
of truth for action-button height/spacing; CadenceActionButton applies it.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

Then update `current_status.md`, commit, **do not push**, report, and stop.
