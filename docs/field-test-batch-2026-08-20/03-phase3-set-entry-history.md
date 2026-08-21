# P3 — Set entry always shows per-partner history (field-test issue 3)

## Problem

> On the set entry view, ALWAYS show previously completed workout weight/rep
> history (if any) AND previous current-exercise-previous-weight/reps (if this
> is not the first set) — BUT only per selected partner if there are multiple
> partners, and it MUST update when I change the selected partner.

Two requirements:
1. **Prior-session history** for the selected performer on this exercise
   ("last time I did this").
2. **This-session history** for the selected performer on this exercise when it
   is not their first set ("last set today").
3. Both must re-derive when "Who did this set?" changes.

## What the code does today

- `InlineSetEditorView` (`Cadence/Cadence/Features/Train/InlineSetEditorView.swift`):
  the header shows `config.exerciseName`, `config.setNumberText`, and
  `config.contextText ?? config.recordedText` (`:97-105`).
- `contextText` is built **once per editor open** in
  `SessionView.inlineEditorConfig()` (`SessionView.swift:203-209`):
  ```swift
  let workingSets = session.orderedSets.filter { $0.exercise?.id == exercise.id && !$0.isWarmup }
  let contextText: String? = {
      guard !isEditing, let prior = workingSets.last else { return nil }
      let effort = prior.rpe.map { " · RPE \(Int($0.rounded()))" } ?? ""
      return "Last set \(Format.setLine(prior, unit: settings.unit))\(effort)"
  }()
  ```
  - It is the **last set of the whole exercise** regardless of performer — not
    the selected performer's last set.
  - It is computed from the config (static for the editor's life), so it does
    **not** update when `performerID` changes.
  - It never shows **prior-session** history at all.
- The editor's only performer-sensitive data is `performerDefaults`
  (`SessionView.swift:279-290` → `InlineEditorConfig.PerformerDefault`,
  `SessionViewShared.swift:45-51`: `reps`, `weightKg`, `weight`), used to
  re-target the draft on `performerID` change (`InlineSetEditorView.swift:87-94`).
  It carries no history.
- Prior-session per-performer history **already exists** in the render cache:
  `SessionRenderModel.State` → `contexts[i].performerContexts[j].lastTimeSets`
  (`SessionRenderModel.swift:75-105`), populated per performer at `:371-413`.

## Design

### Carry per-performer history into the editor

Extend `InlineEditorConfig.PerformerDefault` (`SessionViewShared.swift:45-51`)
with two additive fields:

```swift
var lastTimeText: String?   // "185 lb x 5, 190 lb x 6" — prior-session sets for THIS performer
var lastSetThisSession: String?  // "Last set 185 lb x 8 · RPE 7" — last set TODAY for THIS performer
```

Populate in `SessionView.performerDefaults(for:)` (`SessionView.swift:279-290`),
one entry per roster member:

- `lastTimeText` = `SessionRenderModel.lastTimeSegment(label:…, sets: <that performer's lastTimeSets>, unit:…)`
  (the P2 formatter) using the performer's `PerformerContext.lastTimeSets` from
  `cache.state`; `nil` when the performer has no prior-session sets on this
  movement.
- `lastSetThisSession` = formatted from the **selected performer's** last
  working set logged in `session` for this exercise:
  `session.orderedSets.filter { exercise matches && !isWarmup && performedBy == performer }.last`
  → reuse the `"Last set \(Format.setLine(...))\(effort)"` string; `nil` when it
  is their first set of the exercise (or editing).

Both derivations are small; keep the *formatting* in CadenceFeatures (P2's
`setLineText` / a tiny `SetHistoryText` helper) so it is unit-tested, and keep
the SwiftData lookups in `SessionView` (the existing pattern — `resolvedSet`
already mixes cache + repository).

### Render a history card in the editor

`InlineSetEditorView` gains a `historySection` between `performerSection` and
`weightSection`, driven by the **currently selected** default:

```swift
private var selectedDefault: InlineEditorConfig.PerformerDefault? {
    config.performerDefaults.first { $0.performerID == performerID }
}
```

- A card headed `"History"` (id `setEditor.history`) containing:
  - `Last time: <lastTimeText>` (id `setEditor.history.lastTime`), or
    `No previous history for <name>` in secondary when `lastTimeText == nil`.
  - `Last set today: <lastSetThisSession>` (id `setEditor.history.lastSet`), or
    nothing (or "First set of the exercise") when it is their first set.
- Because `performerID` is `@State` and the section reads `selectedDefault`, the
  section **re-derives automatically** on performer change — the requirement's
  "MUST update when I change the selected partner" falls out of SwiftUI's
  recompute; no extra `.onChange` wiring.
- Edit mode (re-attributing a recorded set): show the recorded set's own
  history note; the per-performer re-target logic stays off (`onChange` already
  guards `!config.isEditing`).

### Formatting helper

Reuse P2's `SessionRenderModel.setLineText(_:unit:)`. `Format.setLine`
(`CadenceFeatures/Format.swift`) already exists for a `SetEntry`; keep it.

## Data-model deltas

None. `PerformerDefault` gains two optional `String`s (app-target type, not
persisted).

## Implementation steps

1. `SessionView.performerDefaults(for:)`: add `lastTimeText` + `lastSetThisSession`
   per roster entry using the P2 formatter and the existing `cache.state`
   performer contexts.
2. `InlineEditorConfig.PerformerDefault` (`SessionViewShared.swift`): add the two
   fields.
3. `InlineSetEditorView`: add `selectedDefault` + `historySection`; insert into
   the `VStack` (`:60-66`).
4. Run `swift test`.

## Testing

### Unit tests (CadenceFeaturesTests)

The formatter/text-building is headless-testable:
- `SessionRenderModelTests`:
  - `testLastTimeSegmentPerSelectedPerformer` — the `Me: …; Sam: …` text built
    from two performers' `lastTimeSets`.
  - `testLastTimeSegmentEmptyForNoHistory` — `nil` when empty.
- New `SetHistoryTextTests` (or fold into `SessionRenderModelTests`):
  - `testLastSetThisSessionText` — "Last set 185 lb x 8 · RPE 7" from a
    `SetEntry`-like input.
  - `testLastSetNilForFirstSet` — no this-session set → `nil`.

The **switching-performer-updates** behavior is SwiftUI recompute; the
per-performer text is proven by the two tests above, and the end-to-end proof
goes in the smoke test.

### iPhone smoke test — one focused addition (worth the cost)

The flow already opens the set editor twice (`saveSetInEditor` at
`SmokeLaunchTests.swift:170`, `logPartnerSet` at `:176`). Add, right after the
owner's set saves:

1. Tap `set.add.<exerciseName>` (exercise stays expanded after the save —
   `:173-174` already proves it) to reopen the editor for the **next** set.
2. Assert `setEditor.history.lastSet` exists and its label contains the owner's
   just-logged weight/reps (the "previous current-exercise weight/reps" case).
3. Switch to Sam via `setEditor.performer` → `setEditor.performer.<uuid>`; assert
   `setEditor.history` updates: Sam has no this-session set, so the history card
   either shows `No previous history…` or no `lastSet` line — assert the change
   (`lastSet` no longer shows the owner's line).
4. Cancel (`setEditor.cancel`) and continue the existing `logPartnerSet` flow.

Estimated +~8–12 s to the smoke run. All assertions unguarded (per the standing
rule). If this pushes the one test's runtime badly, keep only steps 2 and the
performer-switch assertion.

## Open questions

- Whether "No previous history" should be explicit text or just absent. The
  user said "ALWAYS show … (if any)"; explicit secondary text ("No previous
  history for Sam") is friendlier and asserted in the smoke test above.
  Decision **D8**.
