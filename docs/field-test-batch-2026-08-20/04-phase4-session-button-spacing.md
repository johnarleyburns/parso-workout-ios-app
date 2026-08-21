# P4 — Active-workout button spacing matches Home (field-test issue 4)

## Problem

> On the active workout view, the vertical space between buttons is not
> consistent — it needs to make the HomeView spacing.

Home's rhythm is `LayoutMetrics` (CadenceFeatures, single source of truth):
**20** between sections / action buttons, **16** page and card padding, **12**
between rows in a card, **10** between a card heading and its first row, **56**
action-button height, **16** corner radius.

## What the code does today

The active-workout surface (`SessionView` + `ExerciseCardView`) is *mostly*
token-driven already:

- `SessionView.scrollContent` — `VStack(spacing: sectionSpacing)` at
  `SessionView.swift:342`, `.padding(pagePadding)` at `:396`. So the full-width
  actions (`Use Previous Workout`, `Add Exercise`, `Done`, `WorkoutControlBar`)
  already sit on the 20 pt rhythm. ✔
- `ExerciseCardView` — `cardHeadingSpacing` at `:39`, `cardPadding` at `:59`,
  `cardRowSpacing` at `:336`, `cardHeadingSpacing` at `:352`. ✔

**The one anomaly:** the in-card action buttons row
(`ExerciseCardView.actionButtons`, `:335-353`) carries an ad-hoc top padding:

```swift
.padding(.top, CGFloat(LayoutMetrics.cardHeadingSpacing) - 8)   // == 10 - 8 == 2 pt
```

Two points of vertical separation above the buttons — effectively no breathing
room — while every other button boundary on the surface uses the card-row (12)
or section (20) token. The buttons also differ internally: `Add set`/`Repeat`
are `.bordered` at `.controlSize(.regular)` beside full-width `CadenceActionButton`s.

## Design

Normalize the active-workout buttons to the Home rhythm. The full-width actions
already inherit it; the fix is the in-card row.

### `ExerciseCardView.actionButtons`

- Replace `.padding(.top, cardHeadingSpacing - 8)` with
  `.padding(.top, CGFloat(LayoutMetrics.cardRowSpacing))` — the same 12 pt used
  between rows inside the card, so `… last set row / Divider / Add set · Repeat`
  reads like every other card row boundary instead of a 2 pt clamp.
- Keep `HStack(spacing: cardRowSpacing)` (12) between the two buttons — that is
  already the card-row token and matches the Home card treatment.

### Audit sweep (verify, don't guess)

Grep the `Train/` folder for hand-tuned spacings on the *active-workout*
surfaces and route each to a token or leave deliberately:
- `ExerciseCardView.swift:352` — the `.padding(.top, 2)` above (the fix).
- `plannedCard` inner `VStack(spacing: 8)` (`SessionView.swift:754`) — inner
  rows of the planned card; acceptable (matches the tokens' spirit), but align
  to `cardRowSpacing` if it visually differs from Home cards.
- `RestTimerBar`/`SessionBanners` — banner internals, not button spacing; leave.
- `WorkoutControlBar` — explicitly exempt per the 2026-08-18 P1 scope note; leave.
- `InlineSetEditorView` — its own surface (P3), not the active-workout buttons; leave.

The acceptance test is **visual**: the in-card `Add set`/`Repeat` row must sit
12 pt below the last row/Divider, and the spacing rhythm top-to-bottom of the
active workout (cards → `Add Exercise` → `WorkoutControlBar`) must read the same
as Home's card stack.

## Data-model deltas

None.

## Implementation steps

1. `ExerciseCardView.actionButtons`: swap the top padding to `cardRowSpacing`;
   remove the `- 8` hack.
2. Optional: align `plannedCard`'s inner spacing to `cardRowSpacing`.
3. `swift test`; launch the simulator and visually compare a partner session's
   button stack against Home (screenshot for the record).
4. If any *new* token is introduced, extend `LayoutMetricsTests`; if only
   existing tokens are used, the existing equality
   (`testWorkoutSurfacesShareHomeSectionSpacing`) already covers the contract.

## Testing

### Unit tests

- `LayoutMetricsTests` already asserts `actionButtonSpacing == sectionSpacing`
  and the Home-surface equality (the 2026-08-19 fix). No new token is
  introduced, so no new unit test is strictly required. If the implementer
  introduces a token for "button-row top inset", add
  `testInCardActionRowPaddingEqualsCardRowSpacing`.

### iPhone smoke test — no new assertion

The smoke flow already asserts `set.add.<exerciseName>` exists and the summary
heights. A pixel-spacing UI assertion is fragile and the one-test rule keeps the
suite fixed; the visual screenshot + the token equality test are the gate.

## Open questions

- None. This is the smallest phase; it exists so the button rhythm regression
  (already reported twice, per `current_status.md`) does not ship a third time.
