# Phase 6 — Coach optimizer, picker and watch migrate; delete `BodyPart`

**Depends on:** Phases 4–5. **UI impact:** yes. **`make smoke` and
`make watch-smoke` required.**

## Problem

After Phase 5 the volume surface is on `MuscleGroup`, but `CoachPlanOptimizer`,
the exercise picker, the watch's custom-exercise flow and several rule types are
still on `BodyPart`. Two dimensions in one codebase is exactly the state this
work exists to end.

## Inventory (measured 2026-08-23)

`grep -rl BodyPart --include=*.swift` → 55 files, 346 references. After Phases
4–5 the remaining owners are:

**CadenceCore:** `BodyPart.swift`, `CoachPlanOptimizer.swift` (≈40 refs, the big
one), `CoachSchedulePreferences.swift`, `ExerciseDiscovery.swift`,
`ExerciseFacetIndex.swift`, `Insight.swift`, `InsightRule.swift`,
`PlanAwareInsightEngine.swift`, `Recommendation.swift`,
`RecommendationEngine.swift`, `RecommendationRule.swift`,
`SessionEligibilityPolicy.swift`, `TrainingEvent.swift`, `TrainingFacts.swift`,
`VolumeLandmarks.swift`, `WeeklyPlan.swift`, `WeeklyStats.swift`,
`WorkoutHistory.swift`, `WorkoutRepository.swift`, `CoachFacts.swift`.

**CadenceFeatures:** `WatchCustomExerciseDefinition.swift`,
`WatchExerciseSelection.swift`, `WatchStrengthFlowModel.swift`,
`WeekVolumePresenter.swift` (done in Phase 5).

**App / Watch:** `WatchAddExerciseView.swift`,
`CoachDecisionCardView+Presentation.swift`, `BodyPartQuickStartView.swift`,
`CoachOverrideConfirmationModifier.swift`, `HomeView.swift`, `PlanningView.swift`,
`RoutineDetailView.swift`, `ProgressView.swift`, `VolumeLandmarkBar.swift`,
`CustomExerciseListView.swift`, `CustomExerciseEditView.swift`,
`ExercisePickerView.swift`, `ExercisePickerView+Controls.swift`.

**Tests:** 14 files, including `BodyPartTests.swift` (delete).

## Order of work inside the phase

1. `CoachPlanOptimizer` (largest, everything else is downstream)
2. Rule/insight/recommendation types
3. Facet index, discovery, picker
4. Watch flow
5. Delete `BodyPart`, the transitional rollups, and the `MuscleCatalog` shim
6. Tests + ratchets

## 1. `CoachPlanOptimizer.swift`

Straight substitution of the dimension: `[BodyPart: Double]` → `[MuscleGroup: Double]`
throughout (`unresolvedDeficits`, `remainingDeficits`, `slotDeficits`, `projected`,
`deficits`, `lowDeficits`, `overMRVAmount`, `coveredParts`, `partsCovered`,
`bestExercise(for:)`, `defaultExercises(for:)`, `targetedParts`). Specific
decisions:

- **The candidate universe is `trackedMuscleGroups`, not `allCases`** — line ~997
  (`Set(BodyPart.allCases.filter { ... })`) becomes
  `schedule.trackedMuscleGroups.filter { ... }`. Without this the optimizer would
  chase `tibialis`.
- `lowerBodyParts: Set<BodyPart> = [.legs, .calves]` (line 271) becomes
  ```swift
  private static let lowerBodyGroups: Set<MuscleGroup> = [
      .quadriceps, .hamstrings, .glutes, .calves, .adductors, .abductors,
      .hipFlexors, .tibialis
  ]
  ```
  and the upper/lower split at lines 282–283 becomes
  `upper = groups.subtracting(lowerBodyGroups).subtracting([.abdominals])`.
- Exercise → groups (lines ~973, ~1059) goes through `VolumeCredit.credits(for:)`
  keys rather than `BodyPart.parts(forMuscleIDs:)`.
- Recovery gating (line ~988) reads `facts.recovery.byGroup`.
- `PlanningTarget.value(for:experience:)` (line ~1014) takes a `MuscleGroup`.
- **Session size guard.** With 13 tracked dimensions instead of 8, a "fill the
  deficits" session can grow. Cap per-session exercises at the existing value
  (find it — `grep -n "maxExercises\|slotsLeft" CoachPlanOptimizer.swift`) and add
  a regression test asserting a generated session for a cold-start user has no
  more exercises than before this phase.

## 2. Rule / insight / recommendation types

- `Insight.part: BodyPart?` → `group: MuscleGroup?`;
  `.addGapsToPlan(deficits: [BodyPart: Double])` → `[MuscleGroup: Double]`.
- Same for `Recommendation.part`.
- `Recommendation.partDefaultExercise(_:)` → `defaultExercise(for: MuscleGroup)`
  using the table in `04-volume-accounting.md` §4.
- `InsightRule` lines 51/151 and `RecommendationRule` line ~146 iterate
  `schedule.trackedMuscleGroups` (ordered by `MuscleGroup.canonicalOrder` for
  determinism).
- `SessionEligibilityPolicy` reads `recovery.byGroup`; its identifier
  `"bodyPart.\(part.rawValue)"` (line 101) becomes `"muscleGroup.\(group.rawValue)"`
  — **check `grep -rn "bodyPart\." Cadence` for any UI depending on that string**
  before changing it.
- `WeeklyPlan.SessionFocus.bodyParts` → `muscleGroups`:
  `.fullBody` → `MuscleGroup.defaultTracked`;
  `.upper` → `[.chest, .lats, .middleBack, .traps, .shoulders, .biceps, .triceps, .forearms]`;
  `.lower` → `[.quadriceps, .hamstrings, .glutes, .calves]`.

## 3. Facets, discovery, picker

- `ExerciseFacetIndex`: `bodyParts` → `muscleGroups`, `byBodyPart` → `byMuscleGroup`,
  `equipmentByBodyPart` → `equipmentByMuscleGroup`, `bodyPartsByEquipment` →
  `muscleGroupsByEquipment`. `ExerciseFacetIndexable.bodyParts` → `muscleGroups`,
  implemented as `Set(VolumeCredit.credits(for: self).keys)` for templates and
  exercises — i.e. **browse by what the movement actually trains**, stabilizers
  excluded. For non-volume-eligible entries fall back to canonicalised
  `primaryMuscles + secondaryMuscles` so stretches stay browsable.
- `ExerciseDiscovery.byBodyPart` → `byMuscleGroup`;
  `suggestions(forMissing: [MuscleGroup], limit:)`.
- `ExercisePickerView` / `+Controls`:
  - `BrowseMode.byBodyPart` → `.byMuscleGroup`; picker label stays
    **"By Muscle Group"** (already the copy).
  - `selectedPart: BodyPart?` → `selectedGroup: MuscleGroup?`.
  - The chip row grows from 8 to 20 chips. Group them by `BodyRegion` in
    `canonicalOrder` and render untracked groups after tracked ones so the common
    ones stay reachable without scrolling. Accessibility ids become
    `picker.muscleGroup.<rawValue>`.
  - `BodyPart.defaultMuscles(forCategory:)` and `BodyPart.parts(forCategory:)`
    (used at lines 188–190 and 224–227 for the "create exercise from search text"
    path) move to `MuscleGroup.defaults(forCategory: ExerciseCategory)`:
    `.push → [.chest, .shoulders, .triceps]`, `.pull → [.lats, .biceps]`,
    `.legs → [.quadriceps, .hamstrings, .glutes]`, `.core → [.abdominals]`,
    `.cardio/.plyometrics/.other → []`.
  - `BodyPart.guessCategory(from:)` moves to `ExerciseCategory.guess(fromName:)`
    verbatim.
- `BodyPartQuickStartView` → `MuscleGroupQuickStartView` (file rename included);
  its 8 tiles become the tracked 13, laid out in the same grid.
- `CustomExerciseEditView.allMuscles` → `MuscleGroup.canonicalOrder`.
- `CustomExerciseListView`, `RoutineDetailView`, `ProgressView`,
  `CoachDecisionCardView+Presentation`, `CoachOverrideConfirmationModifier`,
  `HomeView`, `PlanningView`: mechanical renames.

## 4. Watch

`WatchCustomExerciseDefinition`, `WatchExerciseSelection`, `WatchStrengthFlowModel`
and `WatchAddExerciseView` carry a body-part picker for creating an exercise on
the wrist. On a 40mm screen, 20 chips is too many: show `MuscleGroup.defaultTracked`
(13) ordered by `canonicalOrder`, with the 7 untracked reachable under a final
`More…` row. Accessibility ids become
`watchCustom.muscleGroup.<rawValue>`; update `WatchAddExerciseView.swift` line
~205 and the two `CadenceFeaturesTests` watch test files.

## 5. Deletions

- `CadenceCore/Sources/CadenceCore/BodyPart.swift` — **delete the file.**
- `BodyPart.part(forGroup:)`, `TrainingFacts.weeklySetsByPart`,
  `frequencyByPart`, `volumeTrendByPart`, `PlanAwareWeeklyAccounting`'s part-keyed
  members, `VolumeLandmarks`' `BodyPart` overload,
  `RecoveryState.byBodyPart`/`softByBodyPart`,
  `TrainingEvent.StrengthEvent.bodyParts`, `WeeklyStats.bodyParts(_:since:)`,
  `CoachSchedulePreferences.excludedCoverageParts` (the **decode-compat branch
  stays**), `TrainingFacts.weeklySetsByMuscle` (superseded by
  `weeklySetsByGroup`).
- `MuscleCatalog` shim — delete; move `canonicalName` to
  `ExerciseNameCanonicalizer` (created in Phase 2) and update the four call sites
  in `CoachSession.swift` (602, 619) and `CoachFacts.swift` (79, 92, 445).
- `CadenceCoreTests/BodyPartTests.swift` — delete; its coverage is replaced by
  `MuscleGroupTests`.

After this phase, `grep -rn "BodyPart" --include=*.swift .` must return **zero**
matches outside `plans/` and `docs/`.

## 6. Tests + guardrails

- Update the 14 test files listed in the inventory: `CoachPlanOptimizerTests`,
  `CoachExerciseVarietyTests`, `CoachPlanConstraintOverrideTests`,
  `CoachBodyweightPrescriptionTests`, `ExerciseDiscoveryTests`,
  `ExerciseFacetIndexTests`, `InsightEngineTests`, `RecencyTests`,
  `RecommendationEngineTests`, `RecommendationPrescriptionTests`,
  `VolumeLandmarksTests`, `WeeklyStatsTests`, and the three watch ones.
- New `CoachPlanOptimizerMuscleGroupTests`:
  - `testOptimizerOnlyTargetsTrackedGroups`
  - `testSessionExerciseCountDoesNotGrowVersusEightPartBaseline`
  - `testUpperLowerSplitAssignsGroupsCorrectly`
  - `testRecoveryGatingUsesGroupWindows`
- `scripts/check-test-pyramid.sh`: update the ratchet entries for every Features
  file whose LOC changed; ratchets may only go **down**. `ExercisePickerView+Controls.swift`
  will grow with 20 chips — if it exceeds its ceiling, extract the chip row into a
  new `MuscleGroupChipRow.swift` rather than raising the ratchet.

## Verification

```
make ci && make smoke && make watch-smoke
```

## Acceptance criteria

- [ ] Zero `BodyPart` references remain in Swift sources.
- [ ] The optimizer targets `trackedMuscleGroups` and does not grow session size.
- [ ] Picker browses 20 muscle groups, grouped by region, tracked first.
- [ ] Watch shows 13 tracked groups with `More…` for the rest.
- [ ] `MuscleCatalog` and `Muscle` are gone.
- [ ] All three gates green; pyramid ratchets updated downward only.

## Commit

`refactor: replace BodyPart with MuscleGroup everywhere`
