# P2 — Collapsed card shows per-partner "last time" (field-test issue 2)

## Problem

> On the active workout view, previous-workout weights and reps should show for
> both partners on the exercise in collapsed form and NOT combined: don't say
> `6/6 sets` etc. With multiple partners it should show like
> `Me: 185 lb x 5, 190 lb x 6; Sam: 125 lb x 20, 130 lb x 15`.

Today the **collapsed** exercise card shows a combined summary; the per-performer
"Last time:" lines exist only in the **expanded** card.

## What the code does today

- `SessionRenderModel.compactSummary(context:unit:)` — `SessionRenderModel.swift:11-32`:
  computes `completed` + `pendingCount` **across all performers** and renders
  `"6/6 sets · 5 reps · 180–200 lb · Sam"` (the "combined" the user objects to).
- Rendered by the collapsed header — `ExerciseCardView.swift:89`
  (`Text(compactSummary).font(.caption).foregroundStyle(.secondary).lineLimit(2)`),
  fed from `SessionView.compactSummary(for:)` (`SessionView.swift:700-702`).
- Per-performer prior-session data already exists and is already fetched per
  performer: `PerformerContext.lastTimeSets: [SetDisplay]` + `label` + `isMe`
  (`SessionRenderModel.swift:75-105`, populated at `:371-413`). It is rendered
  only in the expanded view — `ExerciseCardView.performerContextView`
  (`ExerciseCardView.swift:158-186`), one `Last time: …` line per performer,
  format via `setDisplayLine` (`:188-194`): `"180 lb × 8, 190 lb × 6"` and
  `"BW × 12"`.

So the data, the per-performer fetch, and the formatter **all already exist**.
The change is: render them in the collapsed state, per performer, and stop
combining the set counts.

## Design

### `SessionRenderModel.compactSummary` becomes partner-aware

New behavior (pure, in CadenceFeatures):

- **No partners** (`context.performerContexts.count <= 1`): unchanged — the
  existing `6/6 sets · reps · weight · BW` summary.
- **With partners**: drop the combined set count entirely. Render one segment
  per performer, owner first, in roster order, joined with `; `:
  - `Me: 185 lb x 5, 190 lb x 6` — from the owner's `lastTimeSets`
  - `Sam: 125 lb x 20, 130 lb x 15` — from the partner's `lastTimeSets`
  - A performer with **no prior-session sets** contributes no segment (the user
    asked for previous-workout history; "none" renders nothing, not a fake 0).
  - If **no performer has history**, fall back to the current solo-style counts
    so the card is never blank.
- Segment format: reuse the existing `setDisplayLine` text (`180 lb × 8`,
  `BW × 12`) — it already matches decision D8's lowercase-`x`-equivalent shape
  the user asked for (`185 lb x 5`). Extract the formatter so P2 and P3 share it
  (see below).

Implementation shape — a new pure helper next to `compactSummary`:

```swift
public static func lastTimeSegment(label: String, sets: [SetDisplay],
                                   unit: MeasurementUnitPreference) -> String? {
    guard !sets.isEmpty else { return nil }
    return "\(label): " + sets.map { setLineText($0, unit: unit) }.joined(separator: ", ")
}
```

and `compactSummary` calls it per performer. `setLineText` is the extracted,
shared formatter for one `SetDisplay` (bodyweight → `BW[ + weight] × reps`,
else `weight unit × reps`).

### Collapsed header allows the extra line

`ExerciseCardView.swift:89` — when `context.hasPartners`, the collapsed line may
be long. Change the fixed `lineLimit(2)` to `lineLimit(context.hasPartners ? 3 : 2)`
so two short partner segments fit; keep `.minimumScaleFactor` fallback. (Two
partners × 2 sets each is comfortably ≤3 lines at `.caption`.)

### Expanded view unchanged

`performerContextView` keeps its current "Last time:" label. (P2 does not touch
the expanded card; P3's editor will reuse the same formatter.)

## Data-model deltas

None. `PerformerContext.lastTimeSets` is already computed per performer.

## Implementation steps

1. `SessionRenderModel`: extract `setLineText(_:unit:)` from the view's copy;
   add `lastTimeSegment(label:sets:unit:)`; branch `compactSummary` on
   `hasPartners`.
2. `ExerciseCardView`: use the extracted formatter for `setDisplayLine` (delete
   the local copy at `:188-194`) and relax `lineLimit` for partner sessions.
3. `SessionView` `compactSummary(for:)` is unchanged (already calls the model).
4. Run `swift test`.

## Testing

### Unit tests (CadenceFeaturesTests — `SessionRenderModelTests`)

- `testCompactSummaryWithPartnersShowsPerPerformerLastTime` — build a session
  with two prior sessions (owner and partner each logged Bench Press), then a
  fresh partner session; assert the collapsed summary contains
  `Me: …x…, …x…; Sam: …x…` in roster order and **no** `…/… sets`.
- `testCompactSummaryWithPartnersNeverCombinesSetCounts` — assert the output
  does **not** contain `sets` counts across performers (the `6/6 sets` bug).
- `testCompactSummaryOmitsPartnerWithNoHistory` — partner with no prior session
  → only the owner's segment (or both-omitted fallback).
- `testCompactSummaryFallsBackWhenNobodyHasHistory` — no prior sessions → the
  existing counts summary, never empty.
- `testCompactSummarySoloUnchanged` — solo session output byte-identical to
  today.
- `testLastTimeSegmentBodyweightFormat` — `BW × 12` and `BW + 10 kg × 12`.
- `testSetLineTextUnitAndRoundtrip` — weight formatting for lb/kg and quarter
  values.

### iPhone smoke test — no change

The smoke flow's fresh store has no prior-session history, so no "last time"
segment would render; the assertion would be vacuous. Headless only, per the
standing "assertions behind `if …exists` are worth little" rule. (If the user
wants a smoke assertion anyway, it requires seeding prior history — deferred;
see `decisions.md`.)

## Open questions

- Whether the collapsed partner card should *also* keep the reps/weight range
  from today's plan. The user's ask is specific ("previous workout weights and
  reps"), so this phase replaces the combined summary with per-partner history;
  the plan's target sets stay visible in the expanded card's pending rows. This
  is decision **D5**.
