# Phase 3 — Annotation pipeline: templates, `Exercise` schema, seeding, export

**Depends on:** Phases 1–2. **UI impact:** none yet (Phase 5 renders it).
**Behaviour change:** exercises gain roles/classification; weekly volume math is
still the old code until Phase 4, so the app behaves as before.

## Problem

`ExerciseTemplate` and `Exercise` only carry `primaryMuscles` / `secondaryMuscles`
as opaque strings. There is nowhere to put DB++'s direct/indirect/**stabilizer**
split, `volumeEligible`, training types, modalities, movement patterns, evidence
refs or annotation confidence — all of which Phases 4 and 7 need.

## 1. `ExerciseTemplate` (in `ExerciseLibrary.swift`)

Add, all defaulted so the 124 curated literals keep compiling unchanged:

```swift
/// Muscles the movement trains directly (DB++ `annotation.direct`) — 1.0 set credit.
public var directMuscles: [MuscleGroup]
/// Muscles trained indirectly (DB++ `annotation.indirect`) — 0.5 set credit.
public var indirectMuscles: [MuscleGroup]
/// Muscles that stabilise but are not trained (DB++ `annotation.stabilizers`) — 0.0 credit.
public var stabilizerMuscles: [MuscleGroup]
/// False for stretching, plyometrics, cardio and the handful of strength entries
/// DB++ excludes: the movement contributes NO weekly volume (decision D3).
public var volumeEligible: Bool
/// DB++ `classification.trainingTypes` (strength, powerlifting, olympic_weightlifting,
/// strongman, plyometrics, cardio, stretching, mobility).
public var trainingTypes: [ExerciseTrainingType]
/// DB++ `classification.modalities`.
public var modalities: [ExerciseModality]
/// DB++ `classification.sportContexts`.
public var sportContexts: [ExerciseSportContext]
/// DB++ `annotation.patterns`, raw ids — resolvable to literature via `ExerciseEvidence`.
public var movementPatternIDs: [String]
/// "high" | "medium" | "low" — DB++ annotation confidence.
public var annotationConfidence: String?
/// DB++ / free-exercise-db `exerciseId`, the join key for evidence + imagery.
public var sourceExerciseID: String?
```

Keep `primaryMuscles` / `secondaryMuscles` as **stored** properties (the curated
literals still set them) but make the initializer derive them from
`directMuscles` / `indirectMuscles` when those are supplied and the caller did not
pass explicit muscle arrays — see §3.

### New enums in `ExerciseTaxonomy.swift`

```swift
public enum ExerciseTrainingType: String, CaseIterable, Codable, Sendable {
    case strength, powerlifting
    case olympicWeightlifting = "olympic_weightlifting"
    case strongman, plyometrics, cardio, stretching, mobility
    public var displayName: String   // Strength, Powerlifting, Olympic Weightlifting, Strongman, Plyometrics, Cardio, Stretching, Mobility
}

public enum ExerciseModality: String, CaseIterable, Codable, Sendable {
    case bodyweight
    case freeWeight = "free_weight"
    case machine, cable, band, kettlebell
    case medicineBall = "medicine_ball"
    case loadedObject = "loaded_object"
    case sled, rope
    case foamRoll = "foam_roll"
    case other
    public var displayName: String
}

public enum ExerciseSportContext: String, CaseIterable, Codable, Sendable {
    case powerlifting, weightlifting, strongman, crossfit, gymnastics
    case generalFitness = "general_fitness"
    public var displayName: String
}
```

All three decode leniently: unknown strings from a future DB++ refresh are
**dropped**, never fatal. Implement with
`values.compactMap(ExerciseTrainingType.init(rawValue:))`.

## 2. `ImportedExerciseLibrary.template(from:)` — consume the annotation

Replace the muscle mapping entirely:

```swift
static func template(from record: ExerciseDatabase.Record) -> ExerciseTemplate? {
    let a = record.annotation
    let direct = MuscleGroup.canonicalize(a.direct)
    let indirect = MuscleGroup.canonicalize(a.indirect).filter { !direct.contains($0) }
    let stabilizers = MuscleGroup.canonicalize(a.stabilizers)
        .filter { !direct.contains($0) && !indirect.contains($0) }

    // Non-volume movements (stretching, plyometrics, cardio) have an empty
    // `direct` list by construction. Fall back to the upstream primary muscles so
    // they are still searchable and browsable by muscle — they simply never earn
    // volume credit (decision D3).
    let fallbackPrimary = MuscleGroup.canonicalize(record.source.primaryMuscles)
    let fallbackSecondary = MuscleGroup.canonicalize(record.source.secondaryMuscles)
        .filter { !fallbackPrimary.contains($0) }
    let primary = direct.isEmpty ? fallbackPrimary : direct
    let secondary = direct.isEmpty ? fallbackSecondary : indirect
    guard !primary.isEmpty else { return nil }
    ...
}
```

Everything else in `template(from:)` (equipment map, `category(...)`,
`isLateral`, instructions, imageName, level) is unchanged, except:

- `category(primaryIDs:force:rawCategory:)` takes `[MuscleGroup]` now and reads
  `group.region` instead of `MuscleCatalog.muscle(id)?.region`.
- **Delete `ImportedExerciseLibrary.muscleMap`** — `MuscleGroup.canonical` is the
  one mapping. (This also fixes upstream `neck` being mapped onto `traps`.)

Set the new template fields from `record.classification` /
`record.annotation` / `record.exerciseId`.

**Expected effect (assert it in tests):** `templates.count` stays 873 — every
record has either a non-empty `direct` or a non-empty upstream
`primaryMuscles`. Verify by counting: 200 non-volume-eligible records all have
non-empty `source.primaryMuscles` (they are ordinary upstream records).

## 3. Curated catalog reconciliation

`ExerciseLibrary.curated` is 124 hand-written templates using retired ids
(`upper-chest`, `rear-delts`, `quads`, `abs`, …).

1. Rewrite the literals' `primary:` / `secondary:` arrays to `MuscleGroup` cases.
   Mechanical, via the D7 alias table. **De-duplicate after mapping** — e.g. a
   curated entry with `primary: ["chest","upper-chest"]` becomes
   `primary: [.chest]`, and `secondary: ["triceps","front-delts"]` becomes
   `secondary: [.triceps, .shoulders]`.
2. In `ExerciseLibrary.starter`, when a curated entry resolves to a DB++ record
   (by lowercased name, else via `curatedAlias` → `exerciseId`), the **DB++
   annotation wins** for `directMuscles`, `indirectMuscles`, `stabilizerMuscles`,
   `volumeEligible`, `trainingTypes`, `modalities`, `sportContexts`,
   `movementPatternIDs`, `annotationConfidence`, `sourceExerciseID` — and
   therefore for `primaryMuscles`/`secondaryMuscles` too. The curated entry keeps
   its **name**, `category`, `equipment`, `force`, `mechanics`, `isLateral`.
   Rationale: the curated muscle mapping was our hand-guess at a coarser upstream;
   DB++ is an audited annotation with citations. Record this reversal in the
   comment at `ExerciseLibrary.starter` (it currently says the opposite).
3. Curated entries with **no** DB++ match keep their hand-mapped muscles, get
   `volumeEligible = true`, `trainingTypes = [.strength]`,
   `modalities` derived from `equipment`
   (`barbell/dumbbell/smith → .freeWeight`, `cable → .cable`,
   `machine → .machine`, `bodyweight → .bodyweight`, `band → .band`,
   `kettlebell → .kettlebell`, `plyometric → .bodyweight`, `nil → .other`),
   `sportContexts = [.generalFitness]`, `annotationConfidence = nil`,
   `sourceExerciseID = nil`. `annotationConfidence == nil` is the marker for
   "our mapping, not DB++'s" and Phase 8 labels it as such in the UI.

## 4. `Exercise` (`@Model`) — additive fields

In `Models.swift`, add (all optional/defaulted → CloudKit-safe, decision D12):

```swift
/// DB++ direct-role muscles (`MuscleGroup` raw values); delimited-String storage.
private var directMusclesData: String = ""
private var indirectMusclesData: String = ""
private var stabilizerMusclesData: String = ""
/// Raw `ExerciseTrainingType` / `ExerciseModality` / `ExerciseSportContext` values.
private var trainingTypesData: String = ""
private var modalitiesData: String = ""
private var sportContextsData: String = ""
/// DB++ movement pattern ids, the join key for muscle-role evidence.
private var movementPatternIDsData: String = ""
/// False for stretching / plyometrics / cardio: contributes no weekly volume.
public var volumeEligible: Bool = true
/// "high" | "medium" | "low"; nil means our own mapping, not a DB++ annotation.
public var annotationConfidence: String?
/// free-exercise-db(++) `exerciseId`.
public var sourceExerciseID: String?
```

Plus the matching computed accessors returning `[MuscleGroup]` / `[ExerciseTrainingType]` /
… built on `StringArray` exactly like `primaryMuscles`, and new initializer
parameters (all defaulted, appended **at the end** of the parameter list so no
existing call site breaks).

Add convenience:

```swift
/// Per-planned-set volume credit for a muscle group, honouring `volumeEligible`
/// (decision D3). Direct 1.0, indirect 0.5, everything else 0.
public func setCredit(for group: MuscleGroup) -> Double
/// Every group this exercise credits, with its weight. Empty when not volume-eligible.
public var volumeCredits: [MuscleGroup: Double]
```

`setCredit` reads `directMuscles` / `indirectMuscles` when they are populated and
falls back to `primaryMuscles` / `secondaryMuscles` (canonicalised) when they are
not — that fallback is what keeps a store that has not been re-seeded yet, and
user-created custom exercises, working.

Update `ExerciseLibrary.makeExercise(from:)` to pass the new fields.

## 5. DB++ pattern → `MovementPattern` (decision D9)

Add `MovementPattern.init?(databasePatternID:)` with this complete table
(everything not listed maps to `nil`, and the caller then falls back to the
existing name/category heuristic):

| `MovementPattern` | DB++ pattern ids |
|---|---|
| `.squat` | `squat`, `squat_quad_bias`, `leg_press`, `step_up`, `lunge`, `kneeling_squat` *(not present; ignore)*, `jerk_dip_squat` *(not present; ignore)* |
| `.hinge` | `hip_hinge`, `conventional_deadlift`, `sumo_deadlift`, `rack_pull`, `hip_extension`, `glute_ham_raise`, `kettlebell_swing`, `olympic_clean`, `olympic_snatch`, `olympic_clean_pull`, `olympic_snatch_pull`, `olympic_clean_and_jerk`, `kettlebell_clean`, `kettlebell_snatch`, `kettlebell_sumo_high_pull` |
| `.horizontalPush` | `horizontal_press`, `incline_press`, `decline_press`, `horizontal_press_triceps_bias`, `chest_fly`, `dip_chest_bias` |
| `.horizontalPull` | `horizontal_pull`, `reverse_fly`, `face_pull`, `upright_row`, `shrug` |
| `.verticalPush` | `vertical_press`, `push_press`, `olympic_jerk`, `kettlebell_jerk`, `strongman_overhead`, `thruster`, `snatch_balance`, `dip_triceps_bias`, `bent_press` |
| `.verticalPull` | `vertical_pull`, `muscle_up`, `rope_climb`, `pullover` |
| `.carry` | `loaded_carry`, `farmer_carry`, `strongman_carry`, `sled_push`, `sled_pull`, `drag_with_press`, `power_stairs`, `atlas_stone_load`, `loaded_object_load`, `tire_flip` |
| `.locomotion` | `spider_crawl`, `battle_ropes`, `medicine_ball_slam` |
| `.core` | `trunk_flexion`, `trunk_extension`, `trunk_rotation`, `lateral_flexion`, `anti_extension`, `anti_rotation`, `kettlebell_windmill`, `kettlebell_figure8`, `kettlebell_pirate_ships` |
| `nil` (isolation/joint patterns — heuristic still applies) | `elbow_flexion`, `elbow_flexion_brachioradialis_bias`, `elbow_extension`, `knee_extension`, `knee_flexion`, `hip_flexion`, `hip_abduction`, `hip_adduction`, `shoulder_abduction`, `shoulder_flexion`, `shoulder_internal_rotation`, `shoulder_external_rotation`, `plantar_flexion_straight_knee`, `plantar_flexion_bent_knee`, `dorsiflexion`, `neck_flexion`, `neck_extension`, `neck_lateral_flexion`, `forearm_pronation`, `forearm_supination`, `wrist_flexion`, `wrist_extension`, `grip` |

Then, wherever `MovementPattern` is derived for an exercise today, try
`movementPatternIDs.compactMap(MovementPattern.init(databasePatternID:)).first`
first. Find the current derivation with
`grep -rn "MovementPattern" CadenceCore/Sources/CadenceCore | grep -v "case "`.
If the derivation is name-based inside `MovementFamily.swift`, wire the new
source there and keep the heuristic as the fallback.

## 6. Seeding + migration (`WorkoutRepository.seedStarterLibraryIfNeeded`)

Bump `ExerciseLibrary.seedVersion` 8 → 9.

Add two passes:

**(a) Legacy muscle-id normalisation — runs once for every exercise, custom
included.** For each row where `primaryMuscles` or `secondaryMuscles` contains a
string that is not already a `MuscleGroup` raw value:
1. If `muscleGroups` (the legacy flat-tag field) is empty, write the *pre*-
   migration `primaryMuscles + secondaryMuscles` into it — this preserves the
   user's original ids losslessly and makes the migration reversible (decision D7).
2. `primaryMuscles = MuscleGroup.canonicalize(primaryMuscles).map(\.rawValue)`
3. `secondaryMuscles = MuscleGroup.canonicalize(secondaryMuscles)
      .map(\.rawValue).filter { !primaryMuscles.contains($0) }`
4. Rebuild `searchKeywords` via `ExerciseSearch.keywords(...)`.
5. `updatedAt = Date()`, `changed = true`.

**(b) Annotation backfill for built-ins.** For each built-in row matched to a
template, set the ten new fields **unconditionally** (not "only if empty") — the
DB++ annotation is authoritative and a data refresh must be able to correct a
previous one. Only touch `updatedAt` when a value actually changed, so an
idempotent second run reports `changed == false`.

Never overwrite a **custom** exercise's muscles beyond the canonicalisation in
(a); a custom exercise's `volumeEligible` defaults to `true` and its
`directMuscles`/`indirectMuscles` stay empty (the `setCredit` fallback covers it).

## 7. Export / import

Bump `CadenceExport.currentVersion` 5 → 6 and add the new fields to
`ExportExercise` as **optional** properties (`volumeEligible: Bool?`,
`directMuscles: [String]?`, `indirectMuscles: [String]?`,
`stabilizerMuscles: [String]?`, `trainingTypes: [String]?`, `modalities: [String]?`,
`sportContexts: [String]?`, `movementPatternIDs: [String]?`,
`annotationConfidence: String?`, `sourceExerciseID: String?`), each with a
`decodeIfPresent` default so v5 and older files import exactly as before. On
import, run every muscle array through `MuscleGroup.canonicalize`, so a v1–v5
export written with retired ids lands on the new ontology.

Update `ExportRoundTripFixture` and the round-trip tests accordingly.

## Tests

`CadenceCoreTests/ImportedExerciseLibraryAnnotationTests.swift` (new)

| test | asserts |
|---|---|
| `testTemplateCountUnchanged` | 873 |
| `testVolumeEligibleCountMatchesDatabase` | 673 templates with `volumeEligible == true` |
| `testSquatFixture` | `Barbell Squat` → direct `[.quadriceps, .glutes]`, indirect `[.adductors]`, stabilizers `[.lowerBack, .hamstrings, .calves]`, `volumeEligible`, `trainingTypes == [.strength]`, `modalities == [.freeWeight]`, pattern `["squat"]` |
| `testDeadliftStabilizersAreNotCredited` | `Barbell Deadlift`.`setCredit(for: .lowerBack) == 0`, `.glutes == 1.0`, `.quadriceps == 0.5` |
| `testStretchIsNotVolumeEligibleButKeepsMuscles` | a stretching entry has `volumeEligible == false`, empty `directMuscles`, non-empty `primaryMuscles` |
| `testNeckIsNoLongerMappedToTraps` | a neck movement's direct list contains `.neck` and not `.traps` |
| `testEveryTemplateMuscleIsAMuscleGroup` | all four arrays across all templates |
| `testCuratedEntriesAdoptDatabaseAnnotation` | `Bench Press` (curated, aliased to `Barbell_Bench_Press_-_Medium_Grip`) has `sourceExerciseID` set and direct `[.chest]` |
| `testCuratedOnlyEntriesGetDefaults` | pick a curated entry with no DB++ match: `volumeEligible == true`, `annotationConfidence == nil`, `trainingTypes == [.strength]` |

`CadenceCoreTests/ExerciseMigrationTests.swift` (new, in-memory `ModelContext`)

| test | asserts |
|---|---|
| `testLegacyIdsAreCanonicalized` | insert a custom exercise with `["quads","rear-delts","abs"]`; seed; expect `["quadriceps","shoulders","abdominals"]` |
| `testOriginalIdsArePreservedInLegacyTags` | the same row's `muscleGroups` now holds the pre-migration ids |
| `testMigrationIsIdempotent` | second `seedStarterLibraryIfNeeded` returns `false` and mutates nothing |
| `testBuiltInsGetAnnotations` | after seeding, `Barbell Squat` row has direct/indirect/stabilizers/volumeEligible/sourceExerciseID populated |
| `testCustomExerciseVolumeCreditFallsBackToPrimarySecondary` | custom row with only `primaryMuscles` still returns 1.0 credit |

`CadenceCoreTests/ExportRoundTripTests.swift` (existing, extend)

- `testV6RoundTripPreservesAnnotations`
- `testV5ImportStillWorksAndCanonicalizesMuscles`

## Verification

```
make ci
```
`make smoke` not required (no UI change), but run it anyway before committing
because seeding runs at app launch and a migration crash would only show there.

## Acceptance criteria

- [ ] `ExerciseTemplate` and `Exercise` carry roles, volume eligibility,
      classification, patterns, confidence and source id.
- [ ] DB++ annotation wins over curated hand-mapping where both exist; the
      comment at `ExerciseLibrary.starter` records the reversal.
- [ ] `ImportedExerciseLibrary.muscleMap` deleted.
- [ ] Seeding canonicalises legacy ids for built-in **and** custom rows, preserves
      the originals in the legacy tag field, and is idempotent.
- [ ] Export v6 round-trips the new fields; v5 and older import unchanged.
- [ ] `make ci` green; `make smoke` green.
- [ ] Status note records that a **CloudKit Production schema deploy** is required
      before the next TestFlight build.

## Commit

`feat: adopt db++ muscle roles, volume eligibility and classification`
