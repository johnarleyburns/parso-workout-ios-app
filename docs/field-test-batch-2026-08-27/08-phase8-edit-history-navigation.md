# Phase 8 — Clarify workout edit and history navigation

## Required behavior

- Editing a workout provides large bottom Save and Cancel actions.
- Viewing a workout from History provides a Back button at top left.

## Implementation

- Audit history `WorkoutSummaryView` push/presentation paths and the strength
  workout editor. Give edit mode a bottom safe-area action region with prominent,
  full-width Save and Cancel buttons and stable accessibility identifiers.
- Save persists once, refreshes history/home, and returns to the workout detail.
  Cancel discards the edit draft and returns without mutating the stored workout;
  prompt only if the existing product pattern requires confirmation for dirty
  edits.
- Ensure history detail is always hosted in a navigation context with an explicit
  leading Back action. It should pop to full History, not jump unpredictably to
  Home. Avoid duplicate back controls when the system already supplies one.
- Preserve keyboard avoidance, scrolling, VoiceOver order, and small-screen
  access to both bottom actions.

## Tests and acceptance

- Unit-test edit draft save/cancel transitions and navigation destination state.
  Extend iPhone smoke to open History detail, verify Back, enter Edit, cancel
  without persistence, then save a change and verify persistence.
- Acceptance: Save/Cancel remain large and reachable at the bottom; Back is
  visible at top left for a history-opened workout and returns to History.

