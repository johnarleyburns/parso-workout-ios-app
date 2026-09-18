# Cladiron interface simplification plan

Status: implemented in one UI simplification change, with acceptance coverage
audited through 2026-09-18

## Goal

Make the app feel substantially calmer without removing capability. The primary
loop is: open Cladiron, understand what matters today, start or resume a
workout, and get back to training. Detail, history, research, diagnostics, and
advanced editing remain available through explicit drill-downs.

## Findings

Before this simplification, the root surface exposed Home, Tests, and Progress
as peer tabs. Home then presented start/log actions, completed workouts,
planned workouts, three weekly progress meters, expandable cardio and muscle
volume, observations, readiness, health/watch status, and
contribution/settings controls. The start sheet also presented quick start,
custom, suggested, previous, and seven cardio choices at once. This was
capability-rich but made the first decision harder than it needed to be.

The implementation already has the right boundaries for a simplification:
`WorkoutPlanEditor` is the single review/start/schedule surface, `Progress` and
`History` are navigable destinations, `Settings` owns advanced controls, and
`Transparency & Control` explains automatic work. The redesign therefore uses
progressive disclosure and routing rather than duplicating or deleting domain
logic.

Apple's current Human Interface Guidelines support this direction: use visual
hierarchy and progressive disclosure for hidden content, place disclosure near
the content it reveals, and distinguish an info button from a navigation
disclosure indicator. See Apple's Layout, Disclosure controls, and Lists and
tables guidance.

## Product changes

1. Keep only `Today` and `Progress` as primary tabs. Move standardized Tests
   into an explicit More/Tools destination so it remains available but is not a
   daily navigation peer.
2. Keep one dominant Home action, `Start Workout`. Put `Log Previous Workout`
   behind a clearly labelled `More actions` disclosure.
3. Keep completed and planned workouts visible when present. Keep the compact
   This Week meters visible, but put large observations and readiness cards
   behind labelled disclosures (`Show observations`, `Show readiness`).
4. Add a Home `More` destination containing History, Tests, Exercises, Planned
   Workouts, Coach details, and Settings. Existing deep links and accessibility
   identifiers remain valid where practical.
5. Simplify the start sheet into a short strength chooser and a collapsed
   cardio chooser. The full cardio grid remains one tap away and preserves all
   modalities, GPS choices, and setup flows.
6. Preserve the Workout Plan's existing Start, Schedule, edit, substitution,
   exercise-info, volume, rationale, and citation behavior. Its presentation is
   treated as the focused detail surface; no data or domain operation is moved
   into a new model.
7. Keep automatic work visible: compact status labels remain on Home, and all
   advanced explanation/control paths remain in Transparency & Control.

## Implementation boundaries

- No SwiftData, CloudKit, Watch payload, HealthKit, or generator changes.
- No deletion of legacy records or compatibility routes.
- No simulator execution in this workstream. Package tests, parser checks, and
  static UI-contract checks are the verification gate.
- Do not make a hidden action irreversible. Every collapsed surface has a
  visible label and every advanced route remains reachable from More or the
  contextual screen that owns it.

## Acceptance checks

- Normal launch shows two primary tabs, Today and Progress; no weekly Plan tab
  or Tests tab is exposed.
- Home's first action is Start Workout; More actions reveals Log Previous
  Workout and it still opens the same flow.
- More exposes History, Tests, Exercises, Planned Workouts, Coach details, and
  Settings; each route opens the existing destination.
- Home can reveal observations and readiness explicitly, and This Week still
  expands to cardio, volume, citations, and workout history.
- Start Workout still reaches Quick Start, Custom Workout, Personalized Workout,
  previous workouts, and every cardio modality.
- Workout Plan still supports Start Workout and Schedule this Workout.
- Existing smoke identifiers and retired-Plan assertions remain covered; new
  assertions cover More, the disclosures, and the full cardio chooser.
- `swift test --package-path CadenceCore` remains green. No simulator is run
  locally; release smoke remains an explicit pre-release gate.
