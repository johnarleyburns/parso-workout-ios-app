# FR-1.7 — Edit/delete past sets and sessions

> Edit/delete past sets and sessions.

## Design
- `WorkoutRepository.updateSet`, `deleteSet`, `deleteSession`, all stamping
  `updatedAt` for sync. Editing a set reuses `SetEditorView` in edit mode.

## Mockups
Session screen: tap a set row → edit sheet (same editor, prefilled) → Save or
Delete. Train tab session list: swipe a session to delete (with confirm).

## Implementation
1. `SetEditorView` gains an edit mode (prefill + Delete button).
2. Tap a set row in `SessionView` to edit; swipe-to-delete on set rows.
3. Swipe-to-delete with confirmation on the Train session list.
- a11y ids: `set.delete`, `session.delete`, reuse `set.save`.

## Automated testing
- **Integration:** update changes fields & bumps `updatedAt`; delete removes set
  / session. (Done.)
- **UI:** log a set, tap to edit, change reps, save, assert new value; delete the
  set, assert removed; delete the session from the list, assert gone.
