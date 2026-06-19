# Phase 3 — Workout Plan Editor (Just-in-Time Planning)

## Problem
- Strength workouts (Quick Start, Previous, Coach) launch directly into logging
- No chance to review or customize the plan before the clock starts
- Can't reorder exercises, can't set different reps per set (12-10-8), can't adjust warmup/cooldown
- Coach workout shows no preview at all

## Design

### `WorkoutPlanEditor` — new view

A full-screen editor shown **before** a strength workout starts. Every strength path converges here.

#### Data model: `EditablePlan`
```swift
struct EditablePlan {
    var warmupMinutes: Int          // from settings, editable
    var cooldownMinutes: Int        // from settings, editable
    var exercises: [EditableExercise]
}

struct EditableExercise: Identifiable {
    let id = UUID()
    var name: String                // exercise name
    var sets: [EditableSet]         // each set can have different reps
    var notes: String
}

struct EditableSet: Identifiable {
    let id = UUID()
    var targetReps: Int             // e.g., 12, 10, 8
    var targetWeight: Double?       // optional pre-fill
}
```

This is a **view-level** struct (not SwiftData). On "Start", it's materialized into a real `WorkoutSession` with `ExerciseSet` rows.

#### UI layout (ScrollView)
```
┌────────────────────────────────┐
│ Workout Plan              Edit │  ← nav title
├────────────────────────────────┤
│ ⏱ Warm-up: [5] min        [-][+] │
├────────────────────────────────┤
│ ≡ Bench Press              [×] │  ← drag handle, delete
│   Set 1: 12 reps @ 80 kg      │
│   Set 2: 10 reps @ 80 kg      │
│   Set 3:  8 reps @ 85 kg      │
│   [+ Add Set]                  │
├────────────────────────────────┤
│ ≡ Squat                   [×] │
│   Set 1: 12 reps              │
│   Set 2: 10 reps              │
│   Set 3:  8 reps              │
│   [+ Add Set]                  │
├────────────────────────────────┤
│ [+ Add Exercise]               │
├────────────────────────────────┤
│ ⏱ Cool-down: [5] min     [-][+] │
├────────────────────────────────┤
│ ☐ Use HR monitoring            │  ← toggle from P1
├────────────────────────────────┤
│ ┌──────────────────────────┐   │
│ │      ▶  START            │   │  ← green, full width
│ └──────────────────────────┘   │
└────────────────────────────────┘
```

#### Features
- **Reorder exercises**: drag handles (`.onMove`)
- **Delete exercises**: swipe-to-delete or × button
- **Add exercise**: opens exercise search/picker (reuse existing exercise list from `SessionView`)
- **Edit exercise name**: inline tap-to-edit
- **Per-set reps**: each set has its own rep target (supports 12-10-8 ladders)
- **Per-set weight**: optional pre-fill (from coach, library, or previous workout)
- **Add/remove sets**: per exercise
- **Warmup/cooldown**: stepper controls at top/bottom
- **HR toggle**: at the bottom (from Phase 1)

#### Source paths
| Entry | What populates `EditablePlan` |
|-------|-------------------------------|
| Quick Start | Empty plan (no exercises, just warmup/cooldown from settings) |
| Start with Warm-Up | Empty plan, warmup pre-set |
| Start from Previous | Clone previous session's exercises/sets/reps/weights |
| Start from Library | Library preset's movements + chosen rep scheme |
| Coach Workout | Coach recommendation's prescribed exercises/sets/reps/weights |

All paths converge to: **WeightsStartView** selection → **WorkoutPlanEditor** → [optional HR gate] → **SessionView**

#### On "Start"
1. If `settings.useHRMonitoring`: show `PreWorkoutHRView`, then on continue:
2. If warmup > 0: show `GuidedPhaseOverlay`
3. If countdown > 0: show `PreWorkoutCountdownView`
4. Materialize `EditablePlan` → `WorkoutSession` (via `WorkoutRepository`)
5. Push `SessionView`

### Changes to existing flows

- `WeightsStartView`: All 4 paths (Quick Start, Warm-Up, Previous, Library) now push `WorkoutPlanEditor` instead of calling callbacks directly
- `PlanPreviewView`: **Replaced by** `WorkoutPlanEditor` (same info but editable + consistent)
- `RepSchemePicker`: Still exists — feeds the rep ladder into `WorkoutPlanEditor`
- Coach path: creates an `EditablePlan` from `Recommendation.prescribedSession()`, pushes `WorkoutPlanEditor`

## Files touched
| File | Change |
|------|--------|
| *NEW* `WorkoutPlanEditor.swift` | The just-in-time planning editor |
| `WeightsStartView.swift` | All paths push `WorkoutPlanEditor`; add Coach section |
| `PlanPreviewView.swift` | Removed or gutted (replaced by `WorkoutPlanEditor`) |
| `HomeView.swift` | `launchFromPicker` routes through the editor; remove `pendingPrescription` |
| `WorkoutTypePicker.swift` | Pass coach recommendation to `WeightsStartView` |

## CadenceCore changes
- Potentially add a `WorkoutRepository.startSession(from editablePlan: ...)` overload
- Or keep it view-side: the editor calls existing `createSession` + adds sets programmatically

## Testing
- `swift test` — no CadenceCore logic changes expected
- `xcodebuild` build verification
- Manual: Quick Start → see empty editor → add exercises → reorder → Start
- Manual: Coach → see pre-filled editor → modify reps → Start
- Manual: Previous → see cloned plan → change weight → Start
- Manual: Library → see preset → adjust sets → Start
