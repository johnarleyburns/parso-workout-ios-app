# §03 — Exercise Database (exrx-level catalog + fast search)

> Addresses field note **#4 (database parts)**: distinguish equipment
> (cable/barbell/dumbbell/bodyweight/machine isolateral+non/plyometric…), **a LOT
> more defaults at exrx.net level of thoroughness**, and **fast interactive search
> by name and keyword** where typing "cable" auto-suggests cable exercises and
> keywords include body part, scientific + colloquial muscle names ("lats",
> "pecs"), and push/pull.

Decisions applied: #10 (~300 original entries), #11 (equipment list), #12 (muscle
group + specific muscle + synonym map).

---

## Problem (from the field test)

The current library is **25 hardcoded Swift literals** (`ExerciseLibrary.starter`)
with only `name`, a coarse `ExerciseCategory` (push/pull/legs/core/cardio/other),
and free-text `muscleGroups`. Search is a single case-insensitive **substring on
the name only** (`ExerciseLibrary.search` and `WorkoutRepository.searchExercises`).
So typing "cable" finds only exercises with "cable" literally in the name, not all
cable-equipment movements; "lats" finds nothing; equipment isn't a concept.

## What the code does today

- `CadenceCore/.../ExerciseLibrary.swift` — `ExerciseTemplate{name, category,
  muscleGroups}`; 25 entries; `search()` = name substring.
- `Models.swift` `Exercise` — `name`, `category: String?`, `muscleGroups:
  [String]`, `isCustom`. No equipment, no laterality, no keywords.
- `WorkoutRepository.searchExercises` — name substring over all exercises.
- `WorkoutRepository.seedStarterLibraryIfNeeded` — seeds from the 25 literals if
  the store is empty.

## Research signal — exrx's structure (taxonomy, not data)

ExRx.net classifies each exercise by: **Utility** (basic/auxiliary),
**Mechanics** (compound/isolated), **Force** (push/pull), **Equipment/apparatus**,
and muscle roles: **Target**, **Synergists**, **Stabilizers** (+ dynamic /
antagonist stabilizers). Their *content is licensed* — we replicate the
**structure and thoroughness**, authoring an **original** seed; we do **not** copy
their text/data.

That structure is exactly what enables the search the tester wants: "cable" hits
an *equipment* facet; "pecs"/"lats" hit a *muscle synonym*; "push" hits a *force*
facet — none of which work with name-substring.

Sources:
- https://exrx.net/Questions/ExerciseClassAnalyses
- https://exrx.net/Lists/Directory
- https://exrx.net/Store/Other/Licensing (content is licensed — structure only)

---

## Design

### A. Richer `Exercise` model (faceted)

Add typed facets (all CloudKit-safe: optional or defaulted; raw-stored enums as
String, mirroring the existing `category` pattern):

```
Exercise
  name: String
  category: String?            (existing coarse split)
  equipment: String?           → Equipment enum raw  (NEW)
  isLateral: Bool = false      → isolateral/unilateral machine or movement (NEW)
  mechanics: String?           → .compound/.isolation (NEW)
  force: String?               → .push/.pull/.static (NEW, distinct from category)
  primaryMuscles: [String]     → canonical muscle ids (NEW)
  secondaryMuscles: [String]   → synergists (NEW)
  searchKeywords: [String]     → flattened, normalized tokens (NEW, derived)
  muscleGroups: [String]       (existing; kept for back-compat/migration)
  isCustom, createdAt, updatedAt, originDevice (existing)
```

`Equipment` enum (decision #11):
```
barbell, dumbbell, cable, machine, bodyweight, plyometric,
kettlebell, band, smith
```
- **Isolateral/non:** represented by `isLateral: Bool` (a unilateral machine like
  a single-arm row, or any unilateral movement) rather than a separate equipment
  case, so "machine" + `isLateral` composes cleanly and search can filter both.
- **`force`** is separate from `category`: category is the user's training split
  (push day), `force` is the biomechanical push/pull facet used for keyword
  search ("push" → all pushing movements regardless of split).

### B. Muscle taxonomy + synonym map (decision #12)

A canonical muscle list with **scientific name, colloquial synonyms, and body
region**, shipped in core:

```
public struct Muscle {
    let id: String            // "lats"
    let scientific: String    // "Latissimus Dorsi"
    let synonyms: [String]    // ["lats","lat","back wing"]
    let region: BodyRegion    // .back
}
enum BodyRegion { chest, back, shoulders, arms, core, legs, glutes, fullBody }
```

Example rows: `pecs → Pectoralis Major [chest]`, `lats → Latissimus Dorsi
[back]`, `quads → Quadriceps [legs]`, `hams → Hamstrings [legs]`,
`delts → Deltoid [shoulders]`, `traps → Trapezius [back]`, `bis → Biceps Brachii
[arms]`, `tris → Triceps Brachii [arms]`, `glutes → Gluteus Maximus [glutes]`,
`calves → Gastrocnemius/Soleus [legs]`, `abs → Rectus Abdominis [core]`. ~25–30
canonical muscles cover the seed without going to individual heads (decision #12).

`Exercise.primaryMuscles`/`secondaryMuscles` store **muscle `id`s**; the synonym
map lets search resolve "pecs" → `pecs` → all exercises whose primary/secondary
contains it.

### C. Search keywords (the "type cable, get cables" behavior)

On seed/create, build a normalized `searchKeywords` token set per exercise =
union of:
- name tokens,
- `equipment.rawValue` ("cable", "barbell", …),
- `isLateral ? "isolateral","unilateral","single arm"`,
- `force` ("push"/"pull"),
- every primary/secondary muscle's **id + scientific + all synonyms**,
- the muscle's `region` ("chest","legs",…),
- `mechanics` ("compound"/"isolation").

All lowercased, diacritic-folded. Then ranked search:

```
ExerciseSearch.rank(query, over: [Exercise]) -> [Exercise]
  score = 4·(name prefix) + 3·(name substring)
        + 2·(keyword exact token) + 1·(keyword prefix)
  tie-break: non-custom before custom, then alphabetical
```

So "cable" → high score for everything tagged cable; "lats" → all lat exercises;
"push" → pressing movements; "incline" → name match. Multi-word queries (e.g.
"cable chest") AND the terms across facets.

This is **pure and lives in `CadenceCore`** (replaces `ExerciseLibrary.search`
and powers `WorkoutRepository.searchExercises`), so it's unit-testable headless.

### D. The seed (~300 entries, decision #10)

- Authored as a **bundled JSON resource** in `CadenceCore` (e.g.
  `Resources/exercises.json`), **not** 300 Swift literals — easier to review,
  diff, and extend; loaded via `Bundle.module`. (Add `resources:` to the target
  in `Package.swift`.)
- Coverage target mirrors exrx breadth: for each major muscle/region, multiple
  movements across **barbell / dumbbell / cable / machine / bodyweight /
  kettlebell / band / smith / plyometric**, with isolateral variants where they
  exist. E.g. Chest: barbell/DB/smith bench (flat/incline/decline), cable fly
  (high/low), pec-deck machine, push-up, dip, plyo push-up, single-arm cable
  press (lateral)… repeated per region → ~300.
- Each entry carries: name, category, equipment, isLateral, mechanics, force,
  primaryMuscles, secondaryMuscles. `searchKeywords` is **derived at seed time**,
  not stored in JSON (keeps the file clean, avoids drift).
- **Original authoring** — no exrx text copied (licensing).

### E. Custom exercises (note #4 "enter my own exercises")

`findOrCreateExercise` (already exists) gains the new facets: the §04 "create
exercise" UI lets the user pick equipment, laterality, and tag
muscles/force; keywords derive automatically so a custom exercise is searchable
just like seeded ones. Custom entries rank just below built-ins on ties.

---

## Data-model deltas (consolidated in §07)

- `Exercise`: add `equipment, isLateral, mechanics, force, primaryMuscles,
  secondaryMuscles, searchKeywords` (all optional/defaulted).
- New core (non-`@Model`) types: `Equipment`, `Mechanics`, `Force`, `Muscle`,
  `BodyRegion`, `MuscleCatalog` (synonym map), `ExerciseSearch`.
- New bundled resource `exercises.json` + `Package.swift` `resources:`.
- **Migration:** additive only; existing 25 seeded exercises and any user customs
  keep working (new fields default). Re-seed logic must **upgrade** an empty or
  legacy library to the new seed without duplicating user customs — key the seed
  insert on a `seedVersion` marker rather than "store is empty" (today's
  `seedStarterLibraryIfNeeded` only runs when count==0, so existing testers won't
  get the 300 — add a versioned re-seed that adds missing built-ins by name).

## Mockup — search

```
┌──────────────────────────────┐
│  🔍 cable                    │
│  ── results (ranked) ──       │
│  Cable Fly            cable   │
│  Cable Crossover      cable   │
│  Seated Cable Row     cable   │
│  Single-Arm Cable Row cable·⟂ │   ⟂ = isolateral
│  Triceps Pushdown     cable   │
│  ── or ──                     │
│  ＋ Create "cable" exercise   │
└──────────────────────────────┘
typing "lats"  → Lat Pulldown, Pull-Up, Barbell Row, Straight-Arm Pushdown…
typing "push"  → Bench Press, Overhead Press, Dips, Push-Up, Leg Press…
```

## Implementation steps

1. **Core types:** `Equipment/Mechanics/Force/BodyRegion`, `Muscle` +
   `MuscleCatalog` (synonyms), `ExerciseSearch.rank`. Unit-test ranking.
2. **Extend `Exercise`** with the new fields; add `categoryValue`-style accessors
   for the new raw enums.
3. **Author `exercises.json`** (~300) + load via `Bundle.module`; derive
   `searchKeywords` on seed.
4. **Versioned re-seed** in `WorkoutRepository` (add missing built-ins by name;
   never touch customs).
5. **Repoint search:** `WorkoutRepository.searchExercises` → `ExerciseSearch.rank`
   over fetched exercises (or a SwiftData predicate prefilter for large stores).
6. **Custom-create** carries facets (UI in §04).

## Testing

- **Unit (swift test):** "cable" returns all cable-equipment exercises; "pecs"
  and "lats" resolve via synonyms; "push" returns pushing movements; prefix vs
  substring ranking order; custom ranks after built-in on ties; re-seed adds new
  built-ins without duplicating customs; JSON loads and every entry derives
  keywords.
- **UI (iPhone + iPad):** picker search field → type "cable" → assert multiple
  rows; type a colloquial muscle → assert results; create custom with equipment →
  appears and is searchable by equipment.
- **Accessibility:** result rows expose equipment/laterality in the VoiceOver
  label, not just visually.

## Open questions (resolved)

- Size ~300, exrx-structure, original data (decisions #10). ✔
- Equipment set incl. kettlebell/band/smith; isolateral via `isLateral`
  (decision #11). ✔
- Muscle group + specific muscle + synonyms, no individual heads (decision #12). ✔
