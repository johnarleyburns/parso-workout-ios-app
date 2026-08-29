# Phase 2 — Make workout exercise search responsive

## Reported behavior

Typing in exercise search stalls for seconds per character.

## Implementation

- `ExercisePickerSearch` already keeps the primary normalized index and debounced
  outcome in state; this phase removes the remaining per-keystroke full-index
  rebuild in the best-match path. Built-in exercises now share a cached search
  index and normalized-name lookup, while exact-match checks use a cached set.
- The query task still cancels superseded searches and publishes only the newest
  debounced result. Search and browse behavior remain unchanged.
- Preserve exact-match creation, best-match suggestion, recents/popular/browse,
  muscle/equipment terms, and swap-mode behavior.

## Tests and acceptance

- Existing deterministic `ExerciseSearchIndexTests` cover ranking parity and the
  catalog performance ceiling; the picker now reuses that index for both result
  ranking and best-match selection.
- The existing iPhone picker smoke flow covers typing a query and selecting a
  result.
- Acceptance: input remains interactive and results settle promptly for each
  query; no seconds-per-character stalls on a release build/device.
