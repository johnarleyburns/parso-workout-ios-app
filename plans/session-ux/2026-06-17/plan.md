# Session UX Overhaul — Plan

Date: 2026-06-17
Status: **Approved, implementation starting**

## Overview

Seven items requested. #7 (watch HR fix) is already shipped. Remaining six are
grouped into three phases (A → B → C) by dependency.

## Phase A — Quick wins (independent)

### A1. Swap planned exercise (#2)
- Context menu / swipe on planned exercise cards → ExercisePickerView → replaces
  the exercise name in `plannedExerciseNames` and updates planned sets.
- Files: `SessionView.swift`, `WorkoutRepository.swift` (add swap helper)

### A2. Smart partner rotation (#4)
- When opening the keypad for a new set, pre-select the partner whose last set
  `completedAt` is oldest (or who has no sets). Two-person case: always the one
  who didn't go last.
- Files: `WeightKeypadSheet.swift` (default `selectedPerson`), `SessionView.swift`

### A3. About Coach screen (#6)
- New `CoachAboutView` accessible via (i) button on the Coach card.
- Explains: data sources (all history, 7-day window), live recomputation, how
  editing/finishing affects recommendations, cited studies, goal/experience effect.
- Files: new `Coach/CoachAboutView.swift`, `CoachCardView.swift` (info button)

## Phase B — Inline set entry + per-set unit toggle (#1 + #3)

Tightly coupled — both affect the set entry UI. Build together.

### B1. Inline set entry (#1)
- Replace `WeightKeypadSheet` sheet with an inline expandable row inside each
  exercise card in SessionView.
- Tapping "Add Set" (or existing set) expands an inline editor:
  ```
  ┌─────────────────────────────────┐
  │ Bench Press                     │
  │ 1. 100 kg × 8                  │
  │ 2. 100 kg × 8                  │
  │ ┌─────────────────────────────┐ │
  │ │ [100] [kg ▾] × [8] [Record]│ │
  │ │ ≈ 220.5 lb    [+][-]       │ │
  │ └─────────────────────────────┘ │
  │ Repeat last                     │
  └─────────────────────────────────┘
  ```
- Weight TextField (numeric, last-set prefilled), reps stepper, Record button.
- Partner picker inline when partners exist.
- PR preview + opposite-unit conversion inline.

### B2. Per-set unit toggle (#3)
- `[kg|lb]` segmented toggle in the inline editor (defaults to global pref).
- Entry in selected unit; canonical kg on Record.
- Display shows BOTH units on every set row: `100 kg (220.5 lb) × 8`
- Summary uses user's preferred unit as primary.
- No model change — weight stays canonical kg, toggle is UI-only state.

Files: `SessionView.swift` (major rewrite of set entry), `Formatting.swift`
(dual-unit display), `WeightKeypadSheet.swift` (remove or keep as fallback)

## Phase C — Full history editing (#5)

### C1. Editable title, date, duration
- Past workout in edit mode: tappable title → TextField, tappable date →
  DatePicker, tappable duration → editable end time.
- Files: `SessionView.swift`

### C2. Exercise removal
- Swipe-to-delete on exercise cards (deletes all sets, confirmation dialog).
- Files: `SessionView.swift`, `WorkoutRepository.swift`

## Implementation order

| Phase | Items | Branch |
|-------|-------|--------|
| A     | #2 swap, #4 partner, #6 about coach | `session-ux/phase-a` |
| B     | #1 inline entry, #3 unit toggle | `session-ux/phase-b` |
| C     | #5 history editing | `session-ux/phase-c` |

## Already shipped

- #7 Watch HR: WCSession activation on watch, isReachable check on phone,
  actionable error messages, reply-handler fixes. Build succeeded, tests green.
- Library tab: full exercises/routines browsing, RoutineDetailView, Start Workout.
- PreWorkoutHRView transparent background fix.
