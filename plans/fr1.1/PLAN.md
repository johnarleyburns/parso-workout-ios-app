# FR-1.1 — Create session & add exercises from a searchable library

> Create a session and add exercises from a searchable library (with custom
> exercises and categories: push/pull/legs, or muscle group).

## Design
- **CadenceCore** owns the data + logic (shared by both targets, headless-testable):
  - `Exercise` model gains `category` (push/pull/legs/core/cardio/other), `muscleGroups`, `isCustom`.
  - `ExerciseLibrary.starter` seeds ~25 common lifts on first launch.
  - `WorkoutRepository.seedStarterLibraryIfNeeded`, `searchExercises`,
    `findOrCreateExercise`, `createSession`.
- **iOS app**: a **Train** tab (matches mockups) listing sessions with a "+ New
  Workout" button. Inside a session, "Add Exercise" presents a searchable
  picker (`.searchable`) over the library grouped by category, with a "Create
  '<query>'" affordance for custom exercises.

## Mockups
See `mockup.md`. Train tab → New Workout → Session screen → Add Exercise sheet
with search field, category sections, and inline custom-create row.

## Implementation
1. (done in foundation) Models + library + repository methods.
2. `TrainView` — session list, new-workout button, empty state.
3. `SessionView` — header, per-exercise grouped sets, "Add Exercise" button.
4. `ExercisePickerView` — `.searchable`, category sections, custom create row.
5. Seed library on launch; respect category filters.
- Accessibility identifiers: `train.newWorkout`, `session.addExercise`,
  `picker.search`, `picker.create`, `picker.row.<name>`.

## Automated testing
- **Unit/integration (swift test):** seed idempotency, search match,
  find-or-create dedup, create session. (Done — `WorkoutRepositoryTests`.)
- **UI (iPhone + iPad):** launch in UITest mode → Train tab → create workout →
  add a library exercise via search → assert it appears; create a custom
  exercise via the "Create" row → assert it appears.
