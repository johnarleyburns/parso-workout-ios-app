# FR-1.3 — Inline last-time set & current PR while logging

> While logging a set, display the matching last-time set and the current PR for
> that exercise inline.

## Design
- `WorkoutRepository.lastTimeSets(for:excluding:)` returns the most recent prior
  session's working sets for the exercise.
- `WorkoutRepository.currentPR(for:rule:formula:excluding:)` returns the PR value
  under the user's configured `PRRule` + `OneRepMaxFormula`.
- Shown in the exercise card header and in the set editor so context is visible
  while dialing in a set (UC-1 step 2).

## Mockups
Exercise card header: "Last time: 110 × 5, 110 × 4" and "PR: 116 kg e1RM".
Set editor repeats the last-time line at top for reference.

## Implementation
1. `ExerciseContextHeader` view computing last-time + PR via repository.
2. Embed in `SessionView` exercise card and `SetEditorView`.
- a11y ids: `exercise.lastTime`, `exercise.pr`.

## Automated testing
- **Integration:** `lastTimeSets` picks the most recent prior session and
  excludes the current; `currentPR` per rule. (Done.)
- **UI:** seed a prior session for an exercise; open a new session, add that
  exercise; assert the last-time and PR labels are present and correct.
