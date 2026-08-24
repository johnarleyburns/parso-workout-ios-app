# Phase 7 — Suggested workouts: one target, several training styles

**Depends on:** Phases 3, 4, 6. **UI impact:** yes. **`make smoke` required.**

## Problem

The chooser offers `Minimum` / `Medium` / `Maximal` — the same algorithm run at
4, 8 and 12 sets per muscle. In practice the tiers differ only in how much of the
same greedy ordering survives the 20/30/40-set cap, so the user picks between
three lengths of the same workout. What actually varies between real training
populations is the *kind* of movement, and DB++ now tells us that per exercise.

## Design

**One target — the minimum: 4 sets per tracked muscle group, 20 planned sets
total.** Five **styles** vary which movements fill it.

### `SuggestedWorkoutStyle` (replaces `SuggestedWorkoutTier`)

```swift
public enum SuggestedWorkoutStyle: String, CaseIterable, Equatable, Sendable {
    case fitness, bodyweight, powerlifting, olympic, strongman

    public var displayName: String {
        switch self {
        case .fitness: "Fitness"
        case .bodyweight: "Bodyweight"
        case .powerlifting: "Powerlifting"
        case .olympic: "Olympic Weightlifting"
        case .strongman: "Strongman"
        }
    }
    public var planName: String { "\(displayName) Plan" }
    public var subtitle: String {
        switch self {
        case .fitness:      "General gym movements — machines, cables and free weights."
        case .bodyweight:   "No equipment — movements you can load with your own body."
        case .powerlifting: "Squat, bench and deadlift variations and their accessories."
        case .olympic:      "Snatch, clean and jerk variations, pulls and squats."
        case .strongman:    "Carries, loads, drags and odd-object lifts."
        }
    }
}

public let suggestedWorkoutTargetSetsPerGroup = 4
public let suggestedWorkoutPlannedSetCap = 20
```

Style membership, from `SuggestedExerciseCandidate.trainingTypes` /
`.modalities` / `.sportContexts`:

| style | in-style predicate |
|---|---|
| `fitness` | `trainingTypes.contains(.strength) && sportContexts == [.generalFitness]` |
| `bodyweight` | `modalities.contains(.bodyweight)` |
| `powerlifting` | `trainingTypes.contains(.powerlifting)` |
| `olympic` | `trainingTypes.contains(.olympicWeightlifting)` |
| `strongman` | `trainingTypes.contains(.strongman)` |

Pool sizes in the shipped data (volume-eligible only): fitness 573,
bodyweight 74, powerlifting 38, olympic 35, strongman 21.

### Two-pass selection — the style is a bias, never a filter (NFR-8)

No sport pool covers the ontology: Olympic reaches 6 of 20 groups with a direct
role, Powerlifting 6, Strongman 8, Bodyweight 11. So:

1. **Pass 1 — in-style.** Run the existing greedy deficit solver restricted to
   in-style, volume-eligible candidates.
2. **Pass 2 — fallback.** If deficits remain *and* the planned-set cap is not
   reached, continue the same solver over **all** volume-eligible candidates,
   excluding those already chosen.
3. Trim from the tail to the 20-set cap, then recompute remaining deficits from
   the kept list — exactly as today.

Every selected exercise records `isInStyle`; the option exposes
`inStyleExerciseCount` so the UI can say "4 of 5 movements are Olympic lifts".

**Eligibility gate:** only `volumeEligible` candidates may be selected, in either
pass. This is the fix for stretches and plyometric drills appearing in a strength
suggestion.

### Target dimensions

Deficits are computed over `trackedMuscleGroups` only (from
`CoachSchedulePreferences`), not all 20 — otherwise the solver spends slots on
`tibialis`, which has no direct exercise anywhere in the database.

## Type changes (`CadenceCore/SuggestedWorkoutGenerator.swift`)

```swift
public struct SuggestedExerciseCandidate: Equatable, Sendable {
    public let id: String
    public let name: String
    public let mechanics: Mechanics
    public let directMuscles: [MuscleGroup]      // was primaryMuscles: [String]
    public let indirectMuscles: [MuscleGroup]    // was secondaryMuscles: [String]
    public let volumeEligible: Bool
    public let trainingTypes: [ExerciseTrainingType]
    public let modalities: [ExerciseModality]
    public let sportContexts: [ExerciseSportContext]
}

public struct SuggestedWorkoutInput: Equatable, Sendable {
    public let completedSetsByGroup: [MuscleGroup: Double]
    public let candidates: [SuggestedExerciseCandidate]
    public let trackedGroups: Set<MuscleGroup>
    public let preferredSetsPerExercise: Int
    public let trainingGoal: TrainingGoal
}

public struct SuggestedWorkoutOption: Equatable, Sendable {
    public let style: SuggestedWorkoutStyle       // was tier
    public let plan: WorkoutPlan
    public let exercises: [SuggestedWorkoutExercise]
    public let initialDeficits: [MuscleGroup: Double]
    public let remainingDeficits: [MuscleGroup: Double]
    public let plannedSetTotal: Int
    public let inStyleExerciseCount: Int          // new
    public let capTrimmingOccurred: Bool
    public let citationIDs: [String]
}

public struct SuggestedWorkoutBundle: Equatable, Sendable {
    public let options: [SuggestedWorkoutOption]  // one per style, allCases order
    public let diagnostics: SuggestedWorkoutDiagnostics
    public func option(_ style: SuggestedWorkoutStyle) -> SuggestedWorkoutOption
}
```

`SuggestedWorkoutExercise` gains `isInStyle: Bool` and its `contributions` become
`[SuggestedMuscleContribution]` keyed by `MuscleGroup`.

`SuggestedWorkoutDiagnostics`: rename `threeTierGenerationDuration` →
`allStylesGenerationDuration`; keep the rest. Update
`SuggestedWorkoutSignposts.recordGeneration` (signpost name
`"threeTierGeneration"` → `"allStylesGeneration"`).

## Vector index (`SuggestedWorkoutVectorIndex.swift`)

- `SuggestedWorkoutMuscleSpace.muscleIDs` becomes `groups: [MuscleGroup]`, built
  from the input's `trackedGroups` in `MuscleGroup.canonicalOrder` — **not** from
  `allCases`. The bitmask stays `UInt32` (13–20 dimensions fits comfortably).
- `normalizedMuscleID` is replaced by direct `MuscleGroup` membership.
- Weights come from `VolumeCredit` (direct 1.0, indirect 0.5) rather than being
  hard-coded at the two `elements.append` sites.
- The index is built **once** over all volume-eligible candidates; each style pass
  filters by a precomputed `inStyleMask: [Bool]` per style rather than rebuilding.
  Add `styleMembership: [SuggestedWorkoutStyle: [Bool]]` to the index, so five
  styles still cost one index build (keep `indexBuildCount == 1` in diagnostics).
- The name-collapsing group logic is unchanged, except that when two rows collapse
  the surviving candidate takes the **union** of training types/modalities/sport
  contexts and `volumeEligible = lhs || rhs`.

## Solver (`SuggestedWorkoutGenerator.solve`)

Signature becomes
`solve(style:completed:trackedGroups:preferredSets:goal:index:counters:)`.
Body changes:

1. `let target = Double(suggestedWorkoutTargetSetsPerGroup)` (was
   `tier.targetSetsPerMuscle`).
2. Wrap the existing `while let entry = heap.pop()` loop in a helper
   `fill(pool:)` taking a candidate predicate; call it twice —
   `fill(pool: .inStyle(style))` then `fill(pool: .any)` — re-seeding the heap
   with the still-positive deficits between passes.
3. Skip candidates where `!volumeEligible`.
4. Cap: `while choices.count * preferredSets > suggestedWorkoutPlannedSetCap`.
5. Tie-breaking is unchanged (score → compound over isolation → more muscles
   involved → localized name → id), with one addition **before** the name
   tie-break: **in-style beats out-of-style**. This only matters inside pass 2,
   where an out-of-style candidate can tie an in-style one that pass 1 skipped for
   another reason.

Everything else — the deficit heap, generation counters, `recomputeDeficits`,
the credit-capped scoring `min(remaining, plannedSets * weight)` — is unchanged.

## Presenter (`CadenceFeatures/SuggestedWorkoutPresenter.swift`)

- `SuggestedWorkoutChoice.id` becomes `SuggestedWorkoutStyle`.
- `choice(for:)` title = `style.displayName`; subtitle =
  `"\(plannedSetTotal) planned sets · \(styleText) · \(gaps)\(trim)"` where
  `styleText` is `"all \(style.displayName.lowercased()) movements"` when
  `inStyleExerciseCount == exercises.count`, else
  `"\(inStyleExerciseCount) of \(exercises.count) \(style.displayName.lowercased()) movements"`.
- Empty option copy: `"No available \(style.displayName.lowercased()) exercises
  cover this week's gaps."`, disabled.
- `navigationTitle` stays `"View Suggested Workout"`.
- Intro line in `SuggestedWorkoutView.choices` changes from "Choose the weekly set
  target that fits today." to
  **"Every plan closes the same gaps — choose the kind of training you want today.
  You can review and edit any plan before starting."**
- `aboutSteps` rewritten (this is user-visible and must match the engine):
  ```
  "Starts with this week's completed sets, credited from published movement
   analyses: a direct set counts once, an indirect set counts half, and a muscle
   that only stabilises counts zero.",
  "Calculates a 4-set weekly gap for every muscle group you track.",
  "Considers the largest remaining gap first; equal gaps use a fixed
   largest-to-smallest muscle order.",
  "Fills the plan from your chosen training style first — Olympic lifts for
   Olympic, carries and loads for Strongman, and so on — scoring each unused
   movement only for muscles still in deficit, with credit capped at the
   remaining gap.",
  "Falls back to general strength movements only when the style has nothing left
   that closes a gap, so a style narrows the movements without leaving a gap
   unaddressed on purpose.",
  "Trims from the end to a 20-set safety cap and recomputes what is still
   uncovered.",
  "Produces a deterministic suggestion to review and edit, not a medical
   prescription or a guarantee of an individual optimum."
  ```
- `pseudocode` updated to match, referencing one target and the two passes.
- `citationIDs`: keep `iversenTimeEfficient2021` and `pellandFractionalSets2024`,
  **add `pellandDoseResponse2026`** — the direct/indirect credit claim is now
  stated explicitly in step 1 and must cite.

## App wiring (`Cadence/Cadence/Features/Home/`)

- `HomeView+Actions.requestSuggestedWorkout()`: map each `Exercise` to the new
  candidate shape (`directMuscles`, `indirectMuscles`, `volumeEligible`,
  `trainingTypes`, `modalities`, `sportContexts`), and pass
  `completedSetsByGroup: coachFacts.weeklySetsByGroup` and
  `trackedGroups: settings.coachSchedulePreferences.trackedMuscleGroups`.
  Keep both the success and the failure-path `SuggestedWorkoutInput`
  constructions in sync.
- `SuggestedWorkoutView.choices(_:)`: `ForEach` over five choices — already
  generic over `SuggestedWorkoutPresenter.choices(for:)`, so only the intro string
  and identifiers change. Choice button identifiers become
  `suggestedWorkout.style.<rawValue>`.
- `AboutSuggestedWorkoutsView` renders `aboutSteps` / `pseudocode` — no structural
  change, but re-read it to confirm nothing hard-codes "three tiers".
- **Performance:** five options instead of three, over the same single index.
  Keep the existing `os_signpost` instrumentation and record the measured
  `allStylesGenerationDuration` in the status note.

## Tests — `CadenceCoreTests/SuggestedWorkoutGeneratorTests.swift` (rewrite)

| test | asserts |
|---|---|
| `testFiveStylesAreReturnedInCanonicalOrder` | `options.map(\.style) == SuggestedWorkoutStyle.allCases` |
| `testAllStylesUseTheSameFourSetTarget` | `initialDeficits` identical across styles for the same input |
| `testStyleFillsFromItsOwnPoolFirst` | with a candidate set containing 3 olympic + 20 fitness movements, the olympic option's first three picks are the olympic ones |
| `testFallbackEngagesOnlyWhenStyleIsExhausted` | a style pool of one exercise → option contains that exercise plus general fallbacks, `inStyleExerciseCount == 1` |
| `testNonVolumeEligibleCandidatesAreNeverSelected` | seed a stretch with a huge muscle list; it never appears |
| `testUntrackedGroupsAreNotTargeted` | `tibialis` never appears in `initialDeficits` |
| `testPlannedSetCapIsTwenty` | `plannedSetTotal <= 20` for every style |
| `testDeterministicForIdenticalInput` | two runs produce identical options |
| `testInStyleBeatsOutOfStyleOnAScoreTie` | constructed tie |
| `testEmptyStylePoolYieldsAnUnlaunchableOptionRatherThanACrash` | e.g. no strongman candidates at all |
| `testIndexIsBuiltOnce` | `diagnostics.indexBuildCount == 1` with five styles |
| `testCreditCapping` | an exercise with a 1.0 direct role into a 1-set gap contributes 1.0, not 4.0 |

## Tests — `CadenceFeaturesTests/SuggestedWorkoutPresenterTests.swift`

- `testChoiceTitlesAreStyleNames`
- `testSubtitleReportsInStyleShare`
- `testDisabledChoiceCopy`
- `testAboutStepsMatchEngineContract` — assert the steps mention one target, the
  two passes, and the 20-set cap
- `testCitationsResolve` and `testAboutContentContainsNoRawCitationID`
  (both already exist — keep them passing with the added citation)

## Smoke test

The single iPhone flow taps the suggested-workout entry point. Update its
expected button identifier to `suggestedWorkout.style.fitness` and assert the
chooser shows five options. Do not add a test function.

## Verification

```
make ci && make smoke
```

## Acceptance criteria

- [ ] `SuggestedWorkoutTier` is gone; five styles ship.
- [ ] One target (4 sets/tracked group) and one cap (20 planned sets).
- [ ] Style biases selection, never filters it: gaps a style cannot close are
      filled from general strength work, and the option says how much is in-style.
- [ ] Non-volume-eligible movements can never be suggested.
- [ ] The About sheet describes exactly what the engine does, with resolved
      citations and no raw ids.
- [ ] `make ci` and `make smoke` green; generation duration recorded in the
      status note.

## Commit

`feat: suggest one workout target across five training styles`
