# Phase 1 — Rotate Add Set through performers

## Reported behavior

After saving a partner's set, the next Add Set editor defaults to Me. It should
advance to the next performer in the workout's configured order and wrap around.

## Implementation

- Trace `SessionView+Rendering.onAddSet` through `SessionView+Actions` and
  `SessionView+State.inlineEditorConfig`. Make one pure resolver the source of
  truth for the next performer.
- Base the answer on the exercise's most recently logged working set and the
  persisted roster order, not on owner-first assumptions or a session-global
  cursor. For roster `[Me, Sam, Alex]`, saving Sam selects Alex; saving Alex
  selects Me; saving Me selects Sam.
- Warmups and sets for another exercise must not disturb the current exercise's
  rotation. With no working sets, use the first configured performer. If a
  performer was removed, recover to the first valid roster member.
- Keep pending-row planning and Add Set prefill consistent; reuse or extend
  `SetAlternation`/`PerformerSetPlanner` instead of adding view-local logic.

## Tests and acceptance

- Unit-test two- and three-person wraparound, partner-last, partner-first roster,
  per-exercise isolation, warmup exclusion, empty history, and removed-person
  recovery.
- Extend the existing iPhone smoke flow to save Me then partner and assert the
  next editor selects Me; where practical cover three-person order headlessly.
- Acceptance: every successful working-set save makes the next Add Set default
  to the following configured performer, cyclically.

