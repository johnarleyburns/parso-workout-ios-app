# Workout Start Flow Redesign

**Date:** 2026-06-17
**Trigger:** Field-test findings — double HR screen, inconsistent buttons, missing pre-workout planning.

## Problems

1. **Double HR gate** — Outdoor/indoor/interval workouts show `PreWorkoutHRView` twice: once from `HomeView` (centralized gate) and again inside `OutdoorCardioView`/`RecordCardioView`/`IntervalView`.
2. **HR gate always forced** — No way to skip/remember preference. Users who never use HR still see it every time.
3. **Inconsistent start buttons** — "Start Workout", "Start Coach Workout", "Quick Start", "Start with Warm-Up", mixed styles and labels.
4. **No coach workout preview** — Coach workout launches instantly into the session with no chance to review or modify it.
5. **No just-in-time planning** — Strength workouts (Quick Start, Previous, Coach) launch straight into logging. Users can't see/edit the full plan before starting.

## Design Principles

- **One HR gate, one chance.** HR connection is opt-in, remembered, and shown at most once.
- **See before you start.** Every strength workout shows a full editable preview before the clock starts.
- **Consistent UI language.** Every "go" button is green, says "Start", same size.
- **Minimal taps to start.** Coach/previous workouts are one tap away, with editing optional.

---

## Phased Rollout

| Phase | Branch | Scope | Depends on |
|-------|--------|-------|------------|
| P1 | `start-redesign/hr-toggle` | Fix double HR gate; add `useHRMonitoring` toggle to `AppSettings`; remove per-view HR gates; remove "Connect HR Strap" from active views | — |
| P2 | `start-redesign/consistent-buttons` | Rename all start buttons to "Start" (green); remove "Start Coach Workout" from Home; add coach/custom selector to workout type flow | P1 |
| P3 | `start-redesign/workout-preview` | New `WorkoutPlanEditor` view: full editable preview before starting (exercises, sets, reps, order, warmup, cooldown); applies to all strength paths including coach | P2 |

---

## Cross-cutting Decisions

- **HR toggle persistence:** `AppSettings.useHRMonitoring: Bool` in `UserDefaults`. Default `false`. Once the user changes it, we remember their choice.
- **Where the toggle lives:** On the pre-workout "settings" step — i.e., after choosing a workout type but before starting. For cardio this is the goal sheet / interval setup / swim laps screen. For strength this is the new `WorkoutPlanEditor`.
- **"Connect HR Strap" in active workout:** Removed entirely. If HR wasn't connected pre-workout, they restart.
- **Coach vs Custom selector:** When tapping "Start" on Home, the `WorkoutTypePicker` shows. For Strength, `WeightsStartView` gains a top section: "Coach Workout" (shows the recommendation) and the existing paths below it.
- **Just-in-time planning:** A new `WorkoutPlanEditor` that receives a `[PlannedExercise]` (from coach, library, previous, or empty for Quick Start) and lets the user reorder exercises, add/remove exercises, change sets count, change reps per set independently (12-10-8 style), adjust warmup/cooldown time. On "Start", it materializes the plan into a `WorkoutSession`.
