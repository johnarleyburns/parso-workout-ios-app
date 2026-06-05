# Cadence — Implementation Plan Status

Automated build of FR-1…FR-6 from `REQUIREMENTS.md`. Per-bullet plans live in
`plans/frX.Y/PLAN.md`. Each bullet is designed → implemented → tested (unit +
integration + **iPhone & iPad UI tests**) → reviewed against its plan.

## Process note
Per-bullet **plan documents** are written before implementation. Implementation
and commits are grouped per **FR** (the bullets within an FR share models and
screens, so shipping them together keeps every commit building and green).
Each FR is pushed on its own `feat/fr-N-*` branch.

## Test surfaces
- **CadenceCore** (`cd CadenceCore && swift test`): pure logic + SwiftData repo.
- **CadenceTests** (Swift Testing, app target): view-model/parsing logic.
- **CadenceUITests** (XCUITest): real flows, run on **iPhone 17** and
  **iPad Pro 11-inch (M5)**, launched in `-uiTest` mode (in-memory store +
  deterministic fake Health/BLE/GPS).

Run UI tests with `-parallel-testing-enabled NO` (simulator cloning is unstable
on this host).

---

## FR-1 Strength logging — ✅ COMPLETE
Branch `feat/fr1-strength`. Core 48 tests ✓ · app unit 9 ✓ · UI 7×2 (iPhone+iPad) ✓

| Bullet | Status | Notes |
|---|---|---|
| FR-1.1 create session + searchable library (custom + categories) | ✅ | `TrainView`, `ExercisePickerView`, `ExerciseLibrary` (25 starter lifts) |
| FR-1.2 multiple sets (weight/reps/RPE/note), mixed within exercise | ✅ | `SetEditorView`, `WorkoutRepository.addSet` |
| FR-1.3 inline last-time + current PR | ✅ | `lastTimeSets`, `currentPR` shown in card + editor |
| FR-1.4 auto-detect PR (configurable rule) | ✅ | `PRCalculator`, PR badge + haptic; rule/formula in Settings |
| FR-1.5 rest timer, auto-start on completion | ✅ | `RestTimerModel` (unit-tested) + `RestTimerBar` |
| FR-1.6 reusable templates | ✅ | `TemplatesView`, `TemplateEditorView`, `startSession(from:)` |
| FR-1.7 edit/delete sets & sessions | ✅ | editor edit/delete, swipe-delete, confirm dialog |

## FR-2 Cardio tracking — ⏳ pending
## FR-3 Daily activity & steps — ⏳ pending
## FR-4 Data, HealthKit & sensors — ⏳ pending
## FR-5 History, PRs & trends — ⏳ pending
## FR-6 Migration & export — ⏳ pending
