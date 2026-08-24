# Phase 2 — The `MuscleGroup` ontology

**Depends on:** Phase 1. **UI impact:** none. **Behaviour change:** none —
`MuscleGroup` is introduced and fully tested, but nothing consumes it yet except
compatibility shims.

## Problem

Two overlapping taxonomies exist: `BodyPart` (8 coarse buckets, the volume
dimension) and `MuscleCatalog` (21 fine muscles, the display/search dimension).
Neither matches the evidence-audited ontology DB++ publishes, and five of the 21
fine muscles are populated only by hand-written curated entries (see
`00-overview.md` §2), so they read as permanent red zeros on Home.

## Design

One `MuscleGroup` type replaces both. This phase adds it and re-expresses
`MuscleCatalog` as a thin deprecated shim so nothing breaks; Phases 4–6 migrate
consumers and Phase 6 deletes both `BodyPart` and the shim.

### New file: `CadenceCore/Sources/CadenceCore/MuscleGroup.swift`

```swift
import Foundation

/// The canonical training dimension: free-exercise-db++'s evidence-audited
/// 20-muscle ontology. Raw values are DB++'s strings verbatim, so an annotation
/// can be read straight into this type with no translation table.
///
/// This replaced BOTH the old 8-case `BodyPart` and the 21-entry `MuscleCatalog`
/// (DB++ adoption, 2026-08-23, decision D2). The old fine catalog claimed a
/// resolution the data never had — `front-delts`, `rear-delts`, `upper-chest`,
/// `obliques` and `rhomboids` were reachable only from 19 hand-written entries out
/// of ~1000, so they showed as permanent deficits nobody could close.
public enum MuscleGroup: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case abdominals
    case abductors
    case adductors
    case biceps
    case calves
    case chest
    case forearms
    case glutes
    case hamstrings
    case lats
    case lowerBack = "lower_back"
    case middleBack = "middle_back"
    case neck
    case quadriceps
    case shoulders
    case traps
    case triceps
    case tibialis
    case rotatorCuff = "rotator_cuff"
    case hipFlexors = "hip_flexors"

    public var id: String { rawValue }
}
```

### Descriptors

| case | `displayName` | `scientificName` | `region` | synonyms |
|---|---|---|---|---|
| `abdominals` | Abs | Rectus Abdominis | core | abs, core, six pack, obliques, stomach |
| `abductors` | Abductors | Hip Abductors | legs | abductors, outer thigh, glute medius |
| `adductors` | Adductors | Hip Adductors | legs | adductors, inner thigh, groin |
| `biceps` | Biceps | Biceps Brachii | arms | bis, bicep, biceps |
| `calves` | Calves | Triceps Surae | legs | calves, calf, gastroc, soleus |
| `chest` | Chest | Pectoralis Major | chest | pecs, pec, chest, upper chest |
| `forearms` | Forearms | Forearm Flexors and Extensors | arms | forearms, grip, wrists |
| `glutes` | Glutes | Gluteus Maximus | glutes | glutes, glute, butt, hips |
| `hamstrings` | Hamstrings | Hamstrings | legs | hams, hamstring, posterior chain |
| `lats` | Lats | Latissimus Dorsi | back | lats, lat, wings |
| `lowerBack` | Lower Back | Erector Spinae | back | lower back, erectors, spinal erectors |
| `middleBack` | Mid Back | Rhomboids and Middle Trapezius | back | mid back, middle back, rhomboids, upper back |
| `neck` | Neck | Cervical Flexors and Extensors | back | neck |
| `quadriceps` | Quads | Quadriceps | legs | quads, quad, thighs |
| `shoulders` | Shoulders | Deltoid | shoulders | delts, delt, shoulders, front delts, rear delts, side delts |
| `traps` | Traps | Trapezius | back | traps, trap |
| `triceps` | Triceps | Triceps Brachii | arms | tris, tricep, triceps |
| `tibialis` | Tibialis | Tibialis Anterior | legs | tibialis, shins, shin |
| `rotatorCuff` | Rotator Cuff | Rotator Cuff | shoulders | rotator cuff, cuff, external rotators |
| `hipFlexors` | Hip Flexors | Iliopsoas | legs | hip flexors, psoas, iliopsoas |

The synonym lists deliberately absorb the retired fine-grained names
(`obliques`, `upper chest`, `front delts`, `rear delts`, `rhomboids`) so a user
searching for them still finds the right exercises.

### API on `MuscleGroup`

```swift
public var displayName: String            // table above
public var scientificName: String         // table above
public var synonyms: [String]             // table above
public var region: BodyRegion             // grouping/order only — NEVER a volume dimension

/// Lowercased search tokens: rawValue, displayName, scientificName, synonyms, region.
public var searchTerms: [String]

/// Strict descending average-muscle-mass order, used only to break equal weekly
/// deficits deterministically. An anatomical planning heuristic for the average
/// adult, not a claim about any individual.
public static let descendingMassOrder: [MuscleGroup] = [
    .glutes, .quadriceps, .lats, .chest, .hamstrings, .traps, .shoulders,
    .middleBack, .lowerBack, .calves, .adductors, .triceps, .abdominals,
    .biceps, .forearms, .abductors, .hipFlexors, .neck, .rotatorCuff, .tibialis
]
public static func massPriority(for group: MuscleGroup) -> Int   // index; unknown → .max

/// Programmed by the coach and always shown on Home (decision D4).
public static let defaultTracked: Set<MuscleGroup> = [
    .abdominals, .biceps, .calves, .chest, .forearms, .glutes, .hamstrings,
    .lats, .middleBack, .quadriceps, .shoulders, .traps, .triceps
]

/// Deterministic display order: tracked groups first in `descendingMassOrder`,
/// then untracked in the same order. Callers that want alphabetical sort the
/// `displayName` themselves.
public static let canonicalOrder: [MuscleGroup]

/// Resolves any historical or upstream muscle string to a group.
/// Handles: DB++ raw values, our retired `MuscleCatalog` ids, upstream
/// free-exercise-db strings with spaces ("lower back", "middle back"), and
/// case/whitespace noise. Returns nil for genuinely unknown input.
public static func canonical(_ value: String) -> MuscleGroup?

/// Convenience for a list, order-preserving and de-duplicated.
public static func canonicalize(_ values: [String]) -> [MuscleGroup]
```

`canonical(_:)` implementation: trim whitespace/newlines, lowercase, replace
`-` and spaces with `_`, then look up in a static `[String: MuscleGroup]` table
built from:
- every `rawValue`
- the retired ids: `abs`, `obliques` → `abdominals`; `quads` → `quadriceps`;
  `delts`, `front_delts`, `rear_delts` → `shoulders`; `rhomboids` → `middleBack`;
  `upper_chest` → `chest`
- upstream spellings already normalised by the underscore substitution
  (`lower back` → `lower_back`, `middle back` → `middle_back`)
- `neck` → `neck` (note: the *old* `ImportedExerciseLibrary.muscleMap` mapped
  upstream `neck` onto `traps`; that mis-mapping ends here — DB++ has a real
  `neck` group).

### `BodyRegion`

Keep the existing enum in `ExerciseTaxonomy.swift` unchanged
(`chest, back, shoulders, arms, core, legs, glutes, fullBody`). Add a doc comment
stating it is a **grouping aid only** and must never key volume.

### `MuscleCatalog` compatibility shim

Rewrite `MuscleCatalog` in `ExerciseTaxonomy.swift` as a deprecated forwarder so
Phase 2 compiles without touching 25 call sites:

```swift
@available(*, deprecated, message: "Use MuscleGroup (DB++ adoption, 2026-08-23). Removed in phase 6.")
public enum MuscleCatalog {
    public static var all: [MuscleGroup] { MuscleGroup.canonicalOrder }
    public static func muscle(_ id: String) -> MuscleGroup? { MuscleGroup.canonical(id) }
    public static func searchTerms(for id: String) -> [String] {
        MuscleGroup.canonical(id)?.searchTerms ?? [id.lowercased()]
    }
    public static func massPriority(for id: String) -> Int {
        MuscleGroup.canonical(id).map(MuscleGroup.massPriority(for:)) ?? .max
    }
    public static func canonicalName(_ name: String) -> String { /* moved verbatim */ }
    public static let descendingMassOrder: [String] = MuscleGroup.descendingMassOrder.map(\.rawValue)
}
```

Notes:
- The `Muscle` struct is **deleted**; `MuscleCatalog.all` now yields
  `[MuscleGroup]`. The only consumer of `Muscle` outside the catalog is
  `CustomExerciseEditView.allMuscles` and
  `HomeDashboardPresenter.displayName(for:)`; update both to `MuscleGroup` in this
  phase (two-line changes) rather than keeping a dead struct alive.
- `canonicalName(_:)` (exercise-name canonicalisation) has nothing to do with
  muscles. **Move it** to a new `ExerciseNameCanonicalizer.canonical(_:)` in
  `ExerciseSearch.swift` and leave a forwarding shim on `MuscleCatalog` for this
  phase; Phase 6 deletes the shim and updates the four call sites in
  `CoachSession.swift` / `CoachFacts.swift`.
- Because the shim is `deprecated`, building will emit warnings at the 25 call
  sites, and this repo is warning-free by hard rule. Therefore: **do not** apply
  `@available(deprecated:)` in Phase 2. Add the doc comment
  `/// Deprecated: use `MuscleGroup`. Removed in phase 6.` as plain prose instead,
  and track removal via the phase plan.

## Tests — `CadenceCore/Tests/CadenceCoreTests/MuscleGroupTests.swift` (new)

| test | asserts |
|---|---|
| `testRawValuesMatchDatabaseOntology` | `Set(MuscleGroup.allCases.map(\.rawValue)) == Set(ExerciseDatabase.document!.metadata.muscleOntology)` — the enum can never drift from a data refresh |
| `testAllCasesHaveDistinctDisplayNames` | 20 distinct non-empty display names, each starting uppercase |
| `testEveryCaseHasScientificNameAndSynonyms` | non-empty for all |
| `testSearchTermsAreLowercasedAndUnique` | no uppercase, no duplicates within a group |
| `testRetiredMuscleIdsCanonicalize` | the complete legacy table from `decisions.md` D7, id by id |
| `testUpstreamSpellingsCanonicalize` | `"lower back"`, `"middle back"`, `"Middle Back"`, `" LATS "` |
| `testUnknownReturnsNil` | `""`, `"unicorn"`, `"pecs deck"` |
| `testCanonicalizePreservesOrderAndDeduplicates` | `["quads","abs","quadriceps"] → [.quadriceps, .abdominals]` |
| `testDescendingMassOrderCoversEveryCase` | 20 entries, no duplicates, `massPriority` strictly increasing |
| `testDefaultTrackedIsTheThirteen` | exact set from D4 |
| `testDefaultTrackedGroupsAllHaveDirectExercises` | for each tracked group, ≥1 volume-eligible DB++ record lists it as `direct` — this is the test that would have caught `tibialis` |
| `testCanonicalOrderIsAPermutationOfAllCases` | 20 entries, tracked first |

Also extend `ExerciseSearchTests` (existing) with a case asserting a search for
`"rear delts"` still returns shoulder movements via the synonym absorption.

## Verification

```
make ci
```

## Acceptance criteria

- [ ] `MuscleGroup` exists with the 20 DB++ raw values and full descriptors.
- [ ] `MuscleGroup.canonical` resolves every retired id, every upstream spelling,
      and every DB++ raw value; unknown input returns `nil`.
- [ ] `Muscle` struct deleted; `MuscleCatalog` is a forwarding shim with no
      behaviour of its own except `canonicalName`.
- [ ] `MuscleGroup.defaultTracked` is provably satisfiable from the shipped data.
- [ ] No new warnings. `make ci` green.

## Commit

`feat: add MuscleGroup ontology from exercise db++`
