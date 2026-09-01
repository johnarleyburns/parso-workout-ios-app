# Training-engine contract

The DB++ adoption leaves the future personal-trainer module as an orchestration
layer over deterministic, app-facing seams. It does not need to own exercise
data, volume math, plan generation, observations, progression, or adaptation.

## Composition

Build a fixed `TrainingProfile` and `VolumeTarget` from app state with
`TrainingEngineBridge.trainingProfile` and
`TrainingEngineBridge.volumeTarget`. Build structured intent with
`TrainingEngineBridge.workoutIntent` when a user-selected goal or style is part
of the request. Run the engine through `TrainingEngineBridge.run`, always passing
an explicit `asOf` date.

The normal loop is:

1. `generateFromIntent` or `generatePlan` produces a DB++ `WorkoutPlan`.
2. `serialize` stores optional plan provenance; `deserializePlan` restores it.
3. `trainingHistory` converts finalized app sessions into DB++ history.
4. `deriveState` produces the history-aware training state.
5. `adaptPlan` and `suggestProgression` produce the next engine proposal.
6. `recommendedExercises` maps the selected plan session into the app's
   `CoachSession` shape.
7. `SessionEligibilityPolicy` remains the authoritative app-level gate; readiness,
   pain, recovery, and citations are composed around the engine proposal.

`observationSnapshot` is the app-facing seven-day observation surface for Home.
`adaptiveCoachSession` is the existing façade for an engine-backed Coach card;
the personal-trainer module can use the same bridge primitives without coupling
to SwiftData or DB++ types.

## Intent seam

`TrainingEngineBridge.outcome` is the isolated rejection seam. A future intent
front end may populate a structured `WorkoutIntent`, then handle
`EngineOutcome.needsInput` from `needs_clarification` without changing any
downstream generation, observation, adaptation, eligibility, or citation code.
Natural-language parsing, conversation state, notifications, and multi-week
mesocycle orchestration remain outside this contract.

## Boundary invariant

`TrainingEngineBridge.swift` is the only Swift source file that imports
`FreeExerciseDBPlusPlus`. App-facing code uses bridge-owned value types and
existing `CoachSession`/`WeeklyPlan` façades, so the package can be upgraded or
replaced without leaking package types into UI, persistence, or feature logic.
