# FR-1.2 — Log multiple sets per exercise (weight, reps, RPE, note)

> Log multiple sets per exercise; each set captures weight, reps, optional RPE
> and note. Different weights may have different rep counts within one exercise.

## Design
- `SetEntry` carries `weight` (canonical kg), `reps`, `rpe?`, `note?`, `order`,
  `isWarmup`. Weight is stored in kg; the UI converts to/from the user's unit
  (`MeasurementUnitPreference`) so PR math stays unit-consistent.
- `WorkoutRepository.addSet` assigns the next `order` automatically and stamps
  `updatedAt` for sync. Each set is independent → different weight/reps allowed.

## Mockups
Session screen: each exercise card lists its logged sets (weight × reps, RPE
chip, warmup tag). A "+ Add Set" row opens an inline set editor with weight and
reps steppers/fields, an RPE slider, a warmup toggle, and an optional note.
"Repeat last" one-tap pre-fills the previous set (supports UC-1 ≤2 taps).

## Implementation
1. `SetEditorView` — weight field (unit-aware), reps stepper, RPE slider (1–10,
   optional), warmup toggle, note field, Save.
2. `SessionView` exercise card shows ordered sets + running volume.
3. "Repeat last set" button pre-fills from the exercise's last set in-session.
- a11y ids: `set.weight`, `set.reps`, `set.rpe`, `set.warmup`, `set.note`,
  `set.save`, `set.repeat`, `set.row.<index>`.

## Automated testing
- **Integration:** `addSet` order increment, mixed weights/reps within one
  exercise, update/delete. (Done.)
- **UI (iPhone+iPad):** add two sets with different weights/reps to one
  exercise; assert both rows render; use "Repeat last" and assert a 3rd row.
