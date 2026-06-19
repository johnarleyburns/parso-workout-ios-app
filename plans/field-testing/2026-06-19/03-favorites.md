# 03 — Favorites (Phase D)

## Model
- **Routine favorites:** `AppSettings.favoriteRoutineIDs: Set<String>` in UserDefaults
- **Exercise favorites:** `Exercise.isFavorite: Bool = false` (additive, CloudKit-safe)

## UI — PlanningView
- Routine rows: trailing heart button toggles favorite
- Exercise rows: leading swipe action toggles favorite
- Routines tab: "Favorites" section at top when non-empty

## UI — ExerciseDetailView
- Toolbar heart button toggles `exercise.isFavorite`

## UI — HomeView
- New "Favorites" section between planningButton and thisWeekSection
- Two sub-groups: Routines (from AppSettings) and Exercises (SwiftData query)
- Hidden when both lists empty
- Tappable rows navigate to detail views

## Files
- `Cadence/.../AppSettings.swift` — favoriteRoutineIDs + helpers
- `CadenceCore/.../Models.swift` — isFavorite on Exercise
- `Cadence/.../PlanningView.swift` — favorites section + toggle buttons
- `Cadence/.../ExerciseDetailView.swift` — toolbar heart
- `Cadence/.../HomeView.swift` — favorites section
