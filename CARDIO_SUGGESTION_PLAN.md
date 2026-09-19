# Cardio suggestion plan — Workout for You modality choice

Status: implemented and audited 2026-09-19.

## Goal

When the user taps `Workout for You`, let them choose `Strength` or `Cardio`.
Keep the existing strength suggestion behavior unchanged. Add one deterministic,
reviewable cardio suggestion that uses the user's cardio history and current
weekly cardio gap, then enters the existing cardio setup/recording flow.

## Scope and non-goals

- App-side and CadenceCore only; no DB++ schema or CloudKit record change.
- No replacement of the existing cardio recorder, interval runner, HR bridge,
  Watch handoff, or indoor/outdoor setting.
- No medical or calorie prescription. The suggestion chooses a modality,
  duration, and conservative intensity target for review by the user.
- No automatic workout start. The user always chooses the modality and then
  confirms the existing Start control.
- Scheduling a generated cardio workout is deferred. The current
  `ScheduledWorkout` payload is strength-plan oriented; extending it is a
  separate compatibility change.

## Current architecture findings

- `SuggestedWorkoutGenerator.generatePersonalized` returns a strength-only
  `SuggestedWorkoutOption` and `EditablePlan`.
- `WorkoutPlan`/`EditablePlan` are strength-plan models.
- `CardioType`, `CardioWorkout`, `WeeklyCardioAggregator`, `TimerCardioSetupView`,
  `IntervalSetupView`, `CardioGoalSheet`, and the Watch/HR launch paths already
  provide the execution boundary.
- Cardio history contains type, duration, HR/intensity summaries, source, and
  route presence; it is enough to build a compact value snapshot without
  passing SwiftData models to the generator.

## Value contract

Add to CadenceCore:

1. `SuggestedWorkoutModality` — `strength` or `cardio`, Codable/Hashable/
   Sendable, with display copy and accessibility identifiers.
2. `CardioSuggestionIntensity` — `easy`, `moderate`, or `interval`; each has
   a user-facing label and a launch policy.
3. `CardioSuggestionHistory` — a Sendable value containing type, duration,
   moderate-equivalent minutes, intensity classification, indoor/outdoor
   signal, and start date. No SwiftData references.
4. `CardioSuggestionInput` — history, current week moderate-equivalent
   minutes, weekly target, experience level, and current date. Recent type is
   derived deterministically from the history snapshot.
5. `CardioSuggestion` — chosen type, duration, indoor default, intensity,
   optional interval plan, rationale, and citation IDs.

The contract must be Codable/Equatable where practical so it can be tested and
logged as a value snapshot without private workout data.

## Generator behavior

Implement a pure `CardioSuggestionGenerator`:

1. Compute the remaining weekly moderate-equivalent gap using the existing
   cardio target and clamp it to a safe single-session range.
2. Pick the most recently used usable type; with no history, use the safe
   fallback `run`.
3. Choose duration conservatively: 20–30 minutes for a cold start, otherwise
   a bounded portion of the remaining gap. Never generate zero or an
   unbounded session.
4. Choose intensity: cold-start/beginner/unknown history uses moderate
   continuous work; an established base may receive a moderate session or an
   interval option only when recent history contains sufficient moderate work
   and no recovery warning blocks it. Do not invent HIIT from a single hard
   workout.
5. Choose indoors by default for distance-capable types. The user can switch
   to outdoors in the existing timer setup; indoor mode does not start GPS.
6. Produce a short rationale explaining whether the session closes a weekly
   gap, follows the user's history, or is a conservative starter.
7. Return a launchable value or an explicit failure only when no supported
   cardio type is available. Existing cardio types must not be hidden because
   history is empty.

## UI and routing

1. Change the existing `Workout for You` callback to accept a modality.
2. Add a compact `WorkoutForYouModalityView` with two equal action rows:
   `Strength` and `Cardio`, plus Cancel and an info explanation. Keep the
   existing `Workout for You` identifier stable.
3. Strength selection calls the existing request/generation path unchanged.
4. Cardio selection builds the value snapshot on the app side, runs the pure
   generator off the render path, shows the existing calculating/error/retry
   state, then presents a `CardioSuggestionPreview`.
5. The preview shows type, duration, intensity, indoor default, rationale, and
   an info link. `Start` enters the existing timer or interval review surface;
   `Cancel` returns to the workout picker.
6. Continuous suggestions route to `TimerCardioSetupView`; interval suggestions
   route through the existing HR gate and interval runner. Distance-capable
   continuous types use the existing indoor/outdoor control, with indoor as the
   default. The user can start from the Watch through the existing Watch path.
7. A cardio suggestion must not be represented as a fake strength
   `WorkoutPlan`, and it must not be silently persisted as a scheduled workout.

## Tests and acceptance

Pure tests:

- Empty history produces a launchable moderate starter.
- Recent type selection is deterministic and falls back safely.
- Weekly gap changes duration within bounds and never produces zero.
- Beginners/unknown history never receive an automatic interval suggestion.
- Established history can produce an interval suggestion only under the gate.
- Indoor is the default and outdoor choice is represented separately.
- Input/output are value-only, deterministic, and citation IDs resolve.

App/UI contract tests:

- `Workout for You` opens the Strength/Cardio choice.
- Strength continues to reach the editable Workout Plan.
- Cardio reaches the preview and then the existing cardio setup.
- Loading, failure, retry, and Cancel states are explicit.
- Accessibility identifiers remain stable and no suggestion-ready toast is
  added.

Verification:

- `swift test --package-path CadenceCore`.
- `make guardrails`.
- Generic iOS build with signing disabled.
- `git diff --check`.
- No simulator/device execution during implementation review.

## Completion gate

The feature is complete when every section above is implemented, the strength
path remains behaviorally unchanged, cardio suggestions are generated from a
value snapshot, indoor/outdoor and Watch execution remain explicit, all tests
are green, and the plan audit reports no gap.
