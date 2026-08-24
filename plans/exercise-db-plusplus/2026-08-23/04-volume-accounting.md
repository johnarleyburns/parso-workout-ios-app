# Phase 4 — Weekly volume accounting on the new ontology

**Depends on:** Phases 2–3. **UI impact:** none (Phase 5 renders it).
**Behaviour change:** yes — weekly set counts become DB++-credited. Stretching /
plyometrics / cardio stop contributing; stabilizer-only involvement stops
contributing; `neck` and `rotator_cuff` become real dimensions.

## Design principle for this phase

`TrainingFacts` gains **muscle-group-keyed** facts as the source of truth, and
keeps its `BodyPart`-keyed facts for exactly one more phase, **derived in the same
loop** so the coach optimizer and every rule keep compiling and behaving. Phase 6
deletes the derived ones together with `BodyPart`.

## 1. `TrainingFacts` (`TrainingFacts.swift`)

Add:

```swift
/// Working sets per `MuscleGroup` over the trailing 7 days, credited with the
/// published DB++ model: direct 1.0, indirect 0.5, stabilizer 0.0 — and nothing
/// at all from movements DB++ marks non-volume-eligible (decision D3).
public let weeklySetsByGroup: [MuscleGroup: Double]
/// Distinct training days per muscle group over the same window.
public let frequencyByGroup: [MuscleGroup: Int]
/// Weekly working-set volume trend per muscle group (this week vs prior).
public let volumeTrendByGroup: [MuscleGroup: TrendDirection]
```

Deprecate (keep, derived) `weeklySetsByMuscle` — make it
`weeklySetsByGroup` re-keyed by `rawValue`, so `SuggestedWorkoutInput` and the
Home presenter keep working until Phases 5 and 7 move them over.

### The credit function — one place only

```swift
/// The per-set credit an exercise gives each muscle group. The single source of
/// truth for weekly volume: `TrainingFacts`, `PlanAwareWeeklyAccounting`,
/// `CoachPlanOptimizer` and `SuggestedWorkoutGenerator` all call this, so a
/// screen and a nag can never disagree.
public enum VolumeCredit {
    public static let direct = 1.0
    public static let indirect = 0.5
    public static let stabilizer = 0.0

    /// From a stored exercise. Honours `volumeEligible`; falls back to
    /// primary/secondary when the DB++ role arrays are empty (custom exercises,
    /// or a store that has not been re-seeded).
    public static func credits(for exercise: Exercise) -> [MuscleGroup: Double]

    /// From a template — same rules.
    public static func credits(for template: ExerciseTemplate) -> [MuscleGroup: Double]

    /// From raw role arrays, for callers that carry them loose.
    public static func credits(direct: [MuscleGroup], indirect: [MuscleGroup],
                               volumeEligible: Bool) -> [MuscleGroup: Double]
}
```

Rules, in order: not volume-eligible → `[:]`. Direct wins over indirect when a
group appears in both. Values are `direct`/`indirect` from
`ExerciseDatabase.setCredits` (which defaults to 1.0/0.5/0.0) so a data refresh
that changed the model would flow through automatically.

`TrainingFacts.secondaryWeight` becomes `VolumeCredit.indirect` and the old
constant is removed (grep: it is referenced in `TrainingFacts.swift` and
`PlanAwareInsightEngine.swift`).

### The weekly loop

In `TrainingFacts.build(...)`, replace the per-set body:

```swift
for ws in weekSets {
    let credits = VolumeCredit.credits(for: ws.exercise)
    let day = cal.startOfDay(for: ws.date)
    for (group, weight) in credits {
        setsByGroup[group, default: 0] += weight
        daysByGroup[group, default: []].insert(day)
    }
    // Transitional BodyPart rollup — deleted in phase 6. Preserves today's
    // semantics: a part is credited once per set, not once per member muscle.
    let parts = Set(credits.keys.compactMap(BodyPart.part(forGroup:)))
    ...
}
```

`BodyPart.part(forGroup:)` is a **temporary** helper added in this phase and
deleted in Phase 6:

| `BodyPart` | member `MuscleGroup`s |
|---|---|
| `.legs` | quadriceps, hamstrings, glutes, adductors, abductors, hipFlexors |
| `.back` | lats, middleBack, lowerBack, traps, neck |
| `.chest` | chest |
| `.shoulders` | shoulders, rotatorCuff |
| `.biceps` | biceps |
| `.triceps` | triceps |
| `.calves` | calves, tibialis |
| `.abs` | abdominals |
| — (no part) | forearms |

Weight for the part rollup: `1.0` if any member group got direct credit, else
`0.5` if any got indirect — i.e. `max` over member credits. That reproduces
today's primary/secondary part semantics exactly.

Do the same for the prior-week loop that feeds `volumeTrendByPart`.

## 2. `PlanAwareInsightEngine` / `PlanAwareWeeklyAccounting`

`PlanAwareWeeklyAccounting` currently keys everything by `BodyPart` and applies
`TrainingFacts.secondaryWeight` inline (line ~34). Add group-keyed twins
(`completedSetsByGroup`, `plannedRemainingSetsByGroup`, `projectedSetsByGroup`),
computed via `VolumeCredit`, and derive the part-keyed ones from them with the
same rollup. Planned (not yet performed) sessions carry exercise **names**;
resolve each to a template through `ExerciseLibrary.starter` by lowercased name,
then to credits. Where no template matches, fall back to the planned
recommendation's own muscle strings through `MuscleGroup.canonicalize`.

## 3. `VolumeLandmarks` — per `MuscleGroup`

Replace `baseline(for part: BodyPart)` with `baseline(for group: MuscleGroup)`,
keeping the `bands(for:experience:)` / `zone(sets:for:experience:)` /
`productiveTarget(for:experience:)` shapes and the `ExperienceLevel.volumeScale`
multiplier. Keep a `BodyPart` overload for this phase that takes the **max MEV /
max MAV / max MRV** over the part's member groups; delete it in Phase 6.

Baseline (intermediate) weekly working-set bands:

| group | MEV | MAV | MRV |
|---|---|---|---|
| chest | 8 | 16 | 22 |
| lats | 8 | 16 | 22 |
| middleBack | 6 | 14 | 20 |
| lowerBack | 4 | 10 | 16 |
| traps | 4 | 12 | 20 |
| shoulders | 8 | 16 | 24 |
| biceps | 6 | 14 | 20 |
| triceps | 6 | 14 | 20 |
| forearms | 4 | 10 | 16 |
| abdominals | 6 | 12 | 18 |
| glutes | 6 | 14 | 20 |
| quadriceps | 8 | 16 | 22 |
| hamstrings | 6 | 14 | 20 |
| calves | 6 | 12 | 18 |
| adductors | 4 | 10 | 16 |
| abductors | 4 | 10 | 16 |
| hipFlexors | 2 | 6 | 12 |
| neck | 2 | 6 | 12 |
| rotatorCuff | 2 | 6 | 12 |
| tibialis | 2 | 6 | 12 |

These preserve the existing spread (large regions 8/16/22, arms 6/14/20, small
6/12/18) and extend it to the groups `BodyPart` used to hide inside `legs` and
`back`. The untracked groups (D4) get deliberately low bands so that if a user
opts them in, the coach does not demand a training block for them.

Citations: keep the existing doc reference to the volume dose-response work and
add `pellandDoseResponse2026` alongside `volumeDoseResponse` in the type's doc
comment. `strengthVolumePool` already contains both — nothing to change in the
registry.

## 4. Everything else keyed by weekly sets

Mechanical follow-through; each keeps its current logic and swaps the dimension:

| file | change |
|---|---|
| `CoachFacts.swift` | `RecoveryState.byBodyPart` / `softByBodyPart` gain `byGroup` / `softByGroup` twins built from `VolumeCredit`; `isEligible(...bodyParts:)` and `softPenalty(...)` gain `muscleGroups:` overloads. Keep the part-keyed API until phase 6. `TrainingEvent.StrengthEvent.bodyParts` gains `muscleGroups`. |
| `WeeklyStats.swift` | `bodyParts(_:since:)` gains `muscleGroups(_:since:)` returning `(hit: Set<MuscleGroup>, missing: [MuscleGroup])` over `MuscleGroup.defaultTracked`. |
| `TrainingEvent.swift` | line ~182: build `muscleGroups` from `VolumeCredit.credits(for:)`, derive `bodyParts` from it. |
| `SessionEligibilityPolicy.swift` | lines 75/98/119/129: resolve exercise → groups → `recovery.byGroup`. |
| `InsightRule.swift` | lines 51/151: iterate `MuscleGroup` in `trackedGroups` instead of `BodyPart.allCases`. Insight copy that says "body part" already says "muscle group" per the 2026-08-22 rename — verify with `grep -rn "body part" CadenceCore/Sources`. |
| `RecommendationRule.swift` | line ~146: same. |
| `Insight.swift` / `Recommendation.swift` | `part: BodyPart?` gains `group: MuscleGroup?`; `addGapsToPlan(deficits:)` gains a group-keyed payload. Keep both until phase 6. |
| `Recommendation.partDefaultExercise(_:)` | add a `MuscleGroup` overload; table below. |

`defaultExercise(for group: MuscleGroup)` — used when a rule must name a movement
for a gap. Pick, per group, the highest-`direct`-count volume-eligible curated
name:

```
abdominals → "Crunches"        abductors → "Thigh Abductor"
adductors → "Thigh Adductor"   biceps → "Barbell Curl"
calves → "Standing Calf Raise" chest → "Bench Press"
forearms → "Wrist Curl"        glutes → "Hip Thrust"
hamstrings → "Romanian Deadlift"  lats → "Lat Pulldown"
lowerBack → "Back Extension"   middleBack → "Seated Cable Row"
neck → "Neck Flexion"          quadriceps → "Back Squat"
shoulders → "Overhead Press"   traps → "Barbell Shrug"
triceps → "Triceps Pushdown"   tibialis → "Standing Calf Raise"
rotatorCuff → "Cable External Rotation"  hipFlexors → "Hanging Leg Raise"
```

Before hard-coding these, verify each name resolves in `ExerciseLibrary.starter`
(`swift test` assertion `testEveryDefaultExerciseNameExists`); substitute the
closest real catalog name where one does not.

## 5. `CoachSchedulePreferences`

Add:

```swift
/// Muscle groups the coach programs toward and Home always shows.
/// Defaults to `MuscleGroup.defaultTracked` (decision D4).
public var trackedMuscleGroups: Set<MuscleGroup>
```

Decoding: if the key is present, use it. If absent but the legacy
`excludedCoverageParts` key is present, compute
`MuscleGroup.defaultTracked` minus every group belonging to an excluded
`BodyPart`, so an existing user's opt-outs carry over. Keep
`excludedCoverageParts` as a stored property this phase; delete it in Phase 6
(the decode-compat branch stays forever).

## Tests

`CadenceCoreTests/VolumeCreditTests.swift` (new)

- `testDirectIndirectStabilizerWeights`
- `testNonVolumeEligibleContributesNothing` — a stretch exercise yields `[:]`
- `testDirectWinsWhenAGroupIsBothDirectAndIndirect`
- `testFallsBackToPrimarySecondaryWhenRolesEmpty`
- `testCreditsAreCanonicalized` — an exercise stored with `"quads"` credits `.quadriceps`

`CadenceCoreTests/TrainingFactsVolumeTests.swift` (new, in-memory store)

- `testDeadliftDoesNotCreditLowerBack` — the headline behaviour change
- `testBenchPressCreditsChestOneAndTricepsHalf`
- `testStretchingSetsDoNotCountTowardWeeklyVolume`
- `testFrequencyByGroupCountsDistinctDays`
- `testBodyPartRollupMatchesLegacySemantics` — build facts from a fixed session
  set and assert `weeklySetsByPart` equals the values the pre-phase code produced
  (hard-code them, captured before the change) **except** where the difference is
  an intended consequence of D3; document each intended difference in the test.
- `testVolumeTrendByGroup`

`VolumeLandmarksTests.swift` (existing, extend)

- `testEveryGroupHasOrderedBands` (MEV < MAV < MRV for all 20, at every experience level)
- `testBodyPartOverloadTakesTheMaxOverMembers`

`CoachSchedulePreferencesTests` (existing or new)

- `testTrackedMuscleGroupsDefault`
- `testLegacyExcludedCoveragePartsMigrate`

## Verification

```
make ci
```

Expect a number of existing coach tests to need their **expected values**
updated (not their intent) because stretching/plyometrics and stabilizer credit
no longer inflate weekly sets. Update them and say so in the status note; do not
weaken an assertion to make it pass.

## Acceptance criteria

- [ ] `VolumeCredit` is the only place set credit is computed.
- [ ] `TrainingFacts` exposes group-keyed weekly sets, frequency and trend.
- [ ] Non-volume-eligible movements contribute zero; stabilizers contribute zero.
- [ ] `VolumeLandmarks` has bands for all 20 groups, ordered at every experience
      level.
- [ ] `trackedMuscleGroups` preference exists and migrates old opt-outs.
- [ ] `BodyPart`-keyed facts still exist and still match legacy semantics, so the
      optimizer and rules are untouched this phase.
- [ ] `make ci` green.

## Commit

`feat: credit weekly volume per muscle group with db++ roles`
