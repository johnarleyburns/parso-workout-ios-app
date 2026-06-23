# Bridge Coach Recommended Exercises to Workout Launch

**Status:** draft · **Date:** 2026-06-22

## Problem

`launchDecision(.strengthPlan)` discards the Coach's specific `[RecommendedExercise]` (per-exercise sets, rep range, load, RIR) and calls `pickRoutine` which selects a generic catalog preset. The user sees a canned 5×5 or PPL day instead of the specific prescription Coach generated.

## Desired Behavior

Tapping "Start workout" on the Coach card shows the **exact exercises Coach chose** (e.g., "Back Squat · 3×6–10 · ≤2 RIR, Bench Press · 3×6–10, Barbell Row · 3×6–10"), not an unrelated catalog preset.

## Implementation Steps

### Step 1 — Add `EditablePlan.from(coachSession:)` factory

File: `Cadence/Cadence/Features/Home/WorkoutPlanEditor.swift`

```swift
extension EditablePlan {
    static func from(coach session: CoachSession) -> EditablePlan? {
        guard let exercises = session.exercises, !exercises.isEmpty else { return nil }
        return EditablePlan(
            title: session.title,
            warmupMinutes: 5,
            cooldownMinutes: 0,
            exercises: exercises.map { ex in
                EditableExercise(
                    name: ex.name,
                    sets: (0..<(ex.sets ?? 3)).map { _ in
                        EditableSet(
                            targetReps: ex.repsLow ?? 8,
                            targetWeight: ex.loadKg
                        )
                    },
                    notes: ex.rir.map { "Target ≤\($0) RIR" } ?? ""
                )
            },
            partnerIDs: []
        )
    }
}
```

### Step 2 — Update `launchDecision` in HomeView

Replace the `pickRoutine` call with the Coach's exercises:

```swift
case .strengthPlan:
    if let plan = EditablePlan.from(coach: session) {
        handleEditorStart(plan)
    } else {
        // Fallback: old pickRoutine path
        let twoWeeksAgo = Date().addingTimeInterval(-14 * 86400)
        let recentKeys = sessions.filter { ... }.compactMap(\.planKey)
        let plan = RecommendationEngine.pickRoutine(coachFacts, recentPlanKeys: recentKeys)
        path.append(HomeRoute.coachWorkout(plan))
    }
```

This skips `RoutineDetailView` and goes straight to the HR gate → countdown → `materializePlan` → workout session. The user still sees `WorkoutPlanEditor` (via `handleEditorStart` → `proceedFromHRGate`), so they can confirm/edit.

### Step 3 — Optionally preserve RIR on the session

The `rir` field on `CoachSession.RecommendedExercise` has no equivalent on `WorkoutSession` or `SetEntry`. Two options:

- **A (simple):** Store RIR as a note on the session (`session.notes = "Coach: ≤2 RIR"`) — one line
- **B (future):** Add `targetRIR` to `SetEntry` model — schema change, defer

Start with option A.

### Step 4 — Add tests

File: `CadenceCore/Tests/CadenceCoreTests/CoachLaunchIntegrityTests.swift`

| Test | What it proves |
|------|---------------|
| `testCoachSessionExercisesArePreservedInPlan` | `EditablePlan.from(coachSession:)` maps all exercises with correct names, sets, rep ranges |
| `testEmptyExercisesReturnsNil` | Guard works |
| `testLaunchPayloadDifferentFromPickRoutine` | A Coach session with specific exercises produces a different `EditablePlan` than `pickRoutine` would |

### Step 5 — Clean up unused `coachWorkout` route

Once `launchDecision` no longer calls `pickRoutine`, check if `HomeRoute.coachWorkout(WorkoutPlan)` is still used elsewhere. Keep if needed, otherwise remove.

## Files Changed

| File | Change |
|------|--------|
| `WorkoutPlanEditor.swift` | Add `EditablePlan.from(coachSession:)` static factory |
| `HomeView.swift` | Update `launchDecision(.strengthPlan:)` to use factory |
| `CoachLaunchIntegrityTests.swift` | New test file (3 tests) |

## Risk

| Risk | Mitigation |
|------|------------|
| `handleEditorStart` bypasses `RoutineDetailView` — user sees editor without plan summary | The editor shows all exercises with sets/reps — adequate for confirmation |
| `EditablePlan` doesn't carry `rir` | Store as exercise notes |
| Old `pickRoutine` fallback could still surface wrong exercises if factory returns nil | `from(coachSession:)` only returns nil when `exercises` is nil/empty — the fallback is safe |

## Not In Scope

- Adding `targetRIR` to `SetEntry` model (schema migration, defer to separate PR)
- Removing the old `CoachCardView` / `RecommendationEngine.pickRoutine` — keep until feature flag validates new engine
