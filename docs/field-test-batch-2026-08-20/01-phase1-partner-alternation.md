# P1 — Stable, alternating partner order (field-test issue 1)

## Problem

> When running an active strength workout with partners that was planned,
> sometimes the order changes on an exercise between partners inexplicably; it
> needs to be stable and alternate; sometimes now I see the same name twice
> instead of interleaved.

Two distinct failures, both reproducible in code:

1. The pending-row interleave emits **consecutive same-performer rows** whenever
   one performer is ≥2 rows ahead of the other.
2. The "who's next" rotation used by the free-form Add Set / Repeat paths is
   **session-global**, not per-exercise, so it disagrees with the per-exercise
   pending alternation the card shows.

## What the code does today

### 1a. The pending interleave — `CadenceCore/Sources/CadenceFeatures/SessionRenderModel.swift:313-363`

`build` assembles one group of `PendingSetDisplay` rows **per performer** (owner
first, then partners in `activePartnerIDs` order), where each group holds that
performer's remaining planned sets (`performerSets.count ..< plan.count`), then
calls:

```swift
// SessionRenderModel.swift:432-439
private static func interleaved(_ groups: [[PendingSetDisplay]]) -> [PendingSetDisplay] {
    let depth = groups.map(\.count).max() ?? 0
    var result: [PendingSetDisplay] = []
    for index in 0..<depth {
        for group in groups where index < group.count { result.append(group[index]) }
    }
    return result
}
```

This is a **column-major** round-robin: it emits all column-0 rows first, then
all column-1 rows, etc. When one performer is ahead (e.g. Me has logged 1 of 3
and the partner 0 of 3 → Me owes 2, partner owes 3), the output is
`Me[1], P[0], Me[2], P[1], P[2]` — **two partner rows in a row at the tail**.
The existing test asserts exactly this:

```swift
// SessionRenderModelTests.swift:501-519 testPendingSetsAlternateBetweenPerformers
let order = state.contexts[0].pendingSets.map { ($0.performerID == nil, $0.setIndex) }
XCTAssertEqual(order.map(\.1), [1, 0, 2, 1, 2],
               "Pending rows are not round-robined across performers")
XCTAssertEqual(order.map(\.0), [true, false, true, false, false])
//                     names:   Me, P,  Me, P,  P   ← the "same name twice" the user sees
```

### 1b. The next-performer rotation — `SessionView.swift:939-949`

```swift
private func nextPerson() -> Person? {
    guard hasPartners else { return nil }
    let ordered = roster
    ...
    guard let last = session.orderedSets.reversed().first(where: { set in
        ordered.contains { setPerformedBy(set, person: $0) }
    }), ... else { return ordered.first }
    return ordered[(lastIndex + 1) % ordered.count]
}
```

It scans **the whole session's** sets (every exercise) for the last attributed
set. Consumers:
- editor prefill — `SessionView.swift:176-178` (`pendingPerformerID ?? nextPerson()…`)
- `onRepeat` — `SessionView.swift:666-677` (copies the last set to the *next* person)

Because the rotation is global, after the user finishes an exercise where the
partner went last, the *next* exercise's Add Set picks the owner — while the
card's per-exercise pending rows might say the partner is next (or vice versa).
That mismatch is the "order changes inexplicably": the card and the editor
disagree about whose turn it is.

### 1c. Why pending rows are otherwise stable

`SessionRenderModel.Signature` (`SessionRenderModel.swift:199-241`) includes
`rosterIDs`; `SessionHistoryCache` rebuilds only on signature change; the
interleave is deterministic given (plan, logged counts, roster order). The order
**between saves** is stable — the instability is the two bugs above, plus the
visible re-order after a save when the column interleave flips which performer
leads.

## Design

### New pure type `SetAlternation` — new file `CadenceCore/Sources/CadenceFeatures/SetAlternation.swift`

Foundation-only. Owns both rules so the card, the editor, and `onRepeat` share
one answer.

```swift
public enum SetAlternation {

    /// Evenly-spread interleave of per-performer pending rows. Never emits two
    /// consecutive rows from the same performer while at least two performers
    /// still have outstanding rows. Deterministic: given the same groups it
    /// always returns the same sequence.
    public static func spread(_ groups: [[PendingSetDisplay]]) -> [PendingSetDisplay]
    // Greedy fair-queue: repeatedly emit the next row from the group that is
    // NOT the group of the last emitted row, choosing among non-empty groups in
    // the caller's order; when only one group has rows left, emit its remainder.

    /// Who should enter the next set for an exercise.
    /// - `pendingSets` non-empty → the performer of the first pending row (the
    ///   card's alternation answer).
    /// - `pendingSets` empty (silent/unplanned exercise) → the next member in
    ///   `rosterOrder` after `lastLoggedPerformerID` (the rotation fallback).
    /// Owner is represented by `nil` throughout.
    public static func nextPerformerID(pendingSets: [PendingSetDisplay],
                                       rosterOrder: [UUID?],
                                       lastLoggedPerformerID: UUID?) -> UUID?
}
```

Rules the view must not re-derive:

- **`spread`**: merge groups round-by-round in caller order, but never pick the
  group of the immediately previous emitted row while any other group still has
  rows. Concretely: with Me owing `[1,2]` and P owing `[0,1,2]`, the output is
  `Me[1], P[0], Me[2], P[1], P[2]` → that still ends `P,P`. The user-facing
  rule is stricter: **no same-name-twice while two groups have rows**. So the
  real algorithm is a fair queue:
  ```
  result = []
  lastGroup = nil
  while any group has rows:
      pick the group g with rows where g != lastGroup,
          preferring the caller-order-first among ties
      (if exactly one group still has rows, pick it regardless)
      append g.popFirst()
      lastGroup = g
  ```
  For Me owing 2 / P owing 3 this yields `P0, Me1, P1, Me2, P2` — perfect
  alternation, no repeat. (When only one performer remains, its tail is
  unavoidable and correct.)
- **`nextPerformerID`**: the first pending row wins when rows exist — the editor
  can then never disagree with the row the user is looking at. The rotation
  fallback (silent plan) keeps the existing cycle semantics but **per exercise**:
  `rosterOrder[(index(of: lastLogged) + 1) % count]`, defaulting to the owner.

### `SessionRenderModel.build` uses `SetAlternation.spread`

Replace `interleaved(pendingByPerformer)` at `SessionRenderModel.swift:351`.
Delete `interleaved` (`SessionRenderModel.swift:432-439`).

### `ExerciseContext` exposes the next performer

Add `public var nextPerformerID: UUID?` to `ExerciseContext`
(`SessionRenderModel.swift:126-148`), set in `build` from
`pendingSets.first?.performerID`. The owner is `nil`; with no pending rows the
field is `nil` and callers fall back to rotation (kept in the view, seeded by
the same `SetAlternation.nextPerformerID` so the fallback is still one answer).

### `SessionView.nextPerson(for:)` — per-exercise, shared rule

Replace the global `nextPerson()` (`SessionView.swift:939-949`) with a
per-exercise resolver that calls the pure rule:

```swift
private func nextPerson(for exercise: Exercise) -> Person? {
    guard hasPartners else { return nil }
    let ctx = cache.state.contexts.first { $0.exerciseID == exercise.id }
    let rosterOrder: [UUID?] = rosterEntries.map { $0.isMe ? nil : $0.personID }
    let lastID = session.orderedSets
        .filter { $0.exercise?.id == exercise.id && !$0.isWarmup }
        .last.map { $0.isOwnerSet ? nil : $0.performedBy?.id } ?? nil
    let id = SetAlternation.nextPerformerID(pendingSets: ctx?.pendingSets ?? [],
                                            rosterOrder: rosterOrder,
                                            lastLoggedPerformerID: lastID)
    return id.flatMap { people(for: $0) } ?? ownerPerson()   // nil → owner
}
```

Call sites to change (all `SessionView`):
- editor prefill — `SessionView.swift:176-178`: `nextPerson()` → `nextPerson(for: exercise)` (the `inlineEditorConfig` function has `exercise` in scope).
- `onRepeat` — `SessionView.swift:666-677`: `nextPerson()` → `nextPerson(for: ex)`.
- Keep the old global function **only** if a caller still needs it; prefer removing it so the two surfaces cannot drift again (the standing 2026-08-19 rule: resolve "what should this set be" in one place).

The `nextPerformerID` resolution for `inlineEditorConfig`'s prefill should also
consider the **first pending row for the tapped exercise** — that is already the
case today via `pendingPerformerID` (set by `onTapPending`); this phase only
fixes the free-form Add Set / Repeat path.

## Data-model deltas

None. `ExerciseContext` gains one non-persisted computed/stored field; `State`
is rebuilt per signature as today.

## Implementation steps

1. Add `SetAlternation` to `CadenceCore/Sources/CadenceFeatures/SetAlternation.swift`
   (imports Foundation + CadenceCore only; `PendingSetDisplay` already lives in
   `SessionRenderModel`).
2. `SessionRenderModel`: use `SetAlternation.spread`; delete `interleaved`;
   add `ExerciseContext.nextPerformerID`.
3. `SessionView`: add `nextPerson(for:)`, rewire prefill + `onRepeat`, remove the
   global `nextPerson()` (or reduce it to the rotation-only helper the pure
   function already encodes).
4. Run `swift test`.

## Testing

### Unit tests (CadenceFeaturesTests — `SessionRenderModelTests` + new `SetAlternationTests`)

Update:
- `testPendingSetsAlternateBetweenPerformers` (`SessionRenderModelTests.swift:501-519`)
  — the old expectation `[Me,P,Me,P,P]` **is the bug**. New expectation for the
  same scenario (Me owes 1–2, P owes 0–2): `P0, Me1, P1, Me2, P2`, i.e. names
  `[P, Me, P, Me, P]` — strict alternation, no double.

New:
- `testPendingSetsNeverRepeatAPerformerWhileTwoPerformersHaveRows` — the exact
  field report: after a `Me`-heavy start, the pending list contains **no** two
  consecutive rows from the same performer.
- `testPendingAlternationIsDeterministicAcrossRebuilds` — `build` twice on the
  same session yields equal `pendingSets`.
- `testPendingAlternationIsStableAsSetsAreLogged` — simulate the field sequence
  (Me, Me, P …) and assert each intermediate pending list is alternating and its
  first row is the true next performer.
- `testSpreadSoloGroupEmitsTail` — when only one performer has rows left, their
  remainder is emitted (the unavoidable tail).
- `testNextPerformerIDIsFirstPendingRow` — non-empty pending → first row's
  performer wins.
- `testNextPerformerIDFallsBackToRosterRotation` — empty pending → next after
  `lastLogged` in roster order; owner (`nil`) cycles to the first partner.
- `testNextPerformerIDDefaultsToOwner` — empty pending, no last-logged → `nil`
  (owner).

### iPhone smoke test — no new assertion

The one smoke test already logs an owner set then a partner set
(`saveSetInEditor` then `logPartnerSet`); that sequence exercises the
alternation on the pending rows, but a fresh store's planned counts don't
reproduce the ≥2-gap case, and asserting interleave order in the UI would be
fragile. Coverage for this phase is headless only. (Optional, if the user wants
it: after `saveSetInEditor`, assert the first pending row's `set.performer`
chip is the partner — cheap, but the headless tests already prove it.)

## Open questions

- None blocking. The "no same-name-twice while two groups remain" rule is
  decision **D2** in `decisions.md` — it replaces the column round-robin that
  the old test enshrined.
