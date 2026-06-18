# Phase 2 — Consistent Buttons + Coach Workout Integration

## Problem
- Home has two start buttons: "Start Workout" (hero) and "Start Coach Workout" (smaller)
- Button labels vary: "Start Workout", "Quick Start", "Start with Warm-Up", "Start Coach Workout"
- Coach workout launches directly into logging — no preview, no choice

## Design

### 1. Home button changes
- **"Start Workout"** → **"Start"** (same green gradient hero, shorter label)
- **Remove "Start Coach Workout"** button entirely from Home
- Coach card remains visible — it's informational (recommendation, insights)

### 2. WorkoutTypePicker unchanged
- Still opens as a sheet with hero cards for all workout types
- No label changes here (these are type names like "Strength", "Run", etc.)

### 3. Strength entry: add Coach option to `WeightsStartView`
- New top section: **"Coach Workout"** row showing the current recommendation
  - Tap → goes to the workout preview (Phase 3's `WorkoutPlanEditor`)
  - Subtitle: coach recommendation action text (e.g., "3×10 Bench Press @ 80 kg, RPE 7")
  - If no recommendation available, row is hidden
- Below that, existing sections remain:
  - Quick Start
  - Start with Warm-Up  
  - Start from Previous Workout
  - Start from Library

### 4. Button label standardization
All "launch" buttons across the app become:
| Current label | New label | Where |
|--------------|-----------|-------|
| "Start Workout" (Home hero) | "Start" | `HomeView.startButton` |
| "Start Coach Workout" | *removed* | `HomeView.coachStartButton` |
| "Start Workout" (HR gate) | "Start" | `PreWorkoutHRView` |
| "Continue without HR" | *removed (P1)* | `PreWorkoutHRView` |
| "Quick Start" | "Quick Start" | `WeightsStartView` (keep — it's descriptive, not a final "go") |
| "Start with Warm-Up" | "Warm-Up Start" | `WeightsStartView` (keep) |
| "Start Workout" (Library routine) | "Start" | `RoutineDetailView` |
| "Start" (plan preview) | "Start" | `PlanPreviewView` (already correct) |

### 5. Button style standardization
All final "go" buttons: `.borderedProminent`, `.tint(.green)`, label "Start".

## Files touched
| File | Change |
|------|--------|
| `HomeView.swift` | Rename hero to "Start"; remove `coachStartButton`; pass coach recommendation to `WorkoutTypePicker` / `WeightsStartView` |
| `PreWorkoutHRView.swift` | "Start Workout" → "Start" |
| `RoutineDetailView.swift` | "Start Workout" → "Start" |
| `WeightsStartView.swift` | Add Coach Workout section at top |
| `WorkoutTypePicker.swift` | Pass coach recommendation through to `WeightsStartView` |

## Testing
- `xcodebuild` build verification
- Visual: all start buttons are green and say "Start"
- Flow: tapping Start → Strength → Coach Workout goes to preview (Phase 3)
