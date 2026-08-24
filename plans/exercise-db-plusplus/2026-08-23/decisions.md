# Decisions — DB++ adoption (2026-08-23)

Recorded before implementation. Do not re-litigate a decision here without asking.

### D1 — DB++ replaces free-exercise-db as the single upstream
`johnarleyburns/free-exercise-db-plusplus` (Unlicense) is vendored as a committed
snapshot at `CadenceCore/Sources/CadenceCore/Resources/free-exercise-db-plusplus.json`.
The old `free-exercise-db.json` is **deleted** — DB++ carries every upstream field
byte-identically inside `source`, so nothing is lost. Imagery is untouched: the
873 `exerciseId`s are the same set as the 873 bundled `ExerciseImages/<id>/`
directories. `scripts/update-exercises.sh` is repointed at the DB++ raw URL and
gains schema validation. Attribution names **both** repos (DB++ and its upstream).

### D2 — one canonical dimension: `MuscleGroup`
A new `public enum MuscleGroup: String, CaseIterable, Codable, Sendable` with 20
cases whose **raw values are exactly the DB++ ontology strings** (`abdominals`,
`lower_back`, `middle_back`, `hip_flexors`, `rotator_cuff`, …). It replaces both
`BodyPart` (deleted) and `Muscle`/`MuscleCatalog` (deleted). `BodyRegion` survives
**only** as a grouping/ordering aid for pickers and section headers — never as a
volume dimension.

### D3 — set credits
`direct = 1.0`, `indirect = 0.5`, `stabilizer = 0.0`, exactly as DB++ publishes,
cited to `pellandDoseResponse2026` (PMID 41343037 — the same paper DB++ calls
`fractional_sets_meta_regression_2025`). An exercise with
`volumeEligible == false` contributes **zero** weekly volume no matter what its
muscle lists say; stretching, plyometrics and cardio therefore stop inflating
weekly set counts.

### D4 — tracked vs. observed muscle groups
Default **tracked** (13) — the coach targets these and Home always shows a row:

```
abdominals, biceps, calves, chest, forearms, glutes, hamstrings,
lats, middle_back, quadriceps, shoulders, traps, triceps
```

Default **untracked** (7) — never targeted, shown on Home only when the user has
actually accumulated sets there:

```
abductors, adductors, hip_flexors, lower_back, neck, rotator_cuff, tibialis
```

Rationale: `tibialis` has zero direct exercises in the entire database;
`abductors` has 2, `hip_flexors` 4, `lower_back` 4, `neck` 5, `rotator_cuff` 6 —
a 4-set weekly target for these would nag with no reasonable way to satisfy it,
and `lower_back`/`adductors` earn their volume as stabilizers/indirect work in
compound lifts rather than as programmed targets. The set is a **user preference**
(`CoachSchedulePreferences.trackedMuscleGroups`), so anyone who wants to program
adductors can switch them on.

### D5 — Home "This Week"
The `Muscles` progress row and the expanded `Muscles` subsection are **removed**.
The `Volume` row and the expanded `Volume` list now carry per-`MuscleGroup` rows
(what `Muscles` used to show), on the existing shared 4 / 8 / 12-set scale
(`WeeklySetProgress`, unchanged). Row identifiers become
`home.volume.<muscleGroup.rawValue>`; the `home.muscle.*` and `home.week.muscles`
identifiers disappear.

### D6 — suggested workouts: one target, several styles
`SuggestedWorkoutTier` (minimum / medium / maximal) is replaced by
`SuggestedWorkoutStyle`. Every style uses the **minimum** target — 4 sets per
tracked muscle group, 20 planned sets total cap. Five styles ship:

| style | rawValue | pool signal | in-DB pool size |
|---|---|---|---|
| Fitness | `fitness` | `trainingTypes` contains `strength`, no sport context beyond `general_fitness` | 573 |
| Bodyweight | `bodyweight` | `modalities` contains `bodyweight` | 74 volume-eligible |
| Powerlifting | `powerlifting` | `trainingTypes` contains `powerlifting` | 38 |
| Olympic Weightlifting | `olympic` | `trainingTypes` contains `olympic_weightlifting` | 35 |
| Strongman | `strongman` | `trainingTypes` contains `strongman` | 21 |

A style is a **bias, never a hard filter**: no sport pool can cover the ontology
(Olympic reaches 6 of 20 muscle groups directly), so in-style candidates are
scored with a preference multiplier and the general strength pool fills whatever
the style cannot. Each option discloses how many of its exercises are in-style.
This preserves NFR-8 (the coach suggests, it does not proscribe).

### D7 — persistence is additive; legacy ids canonicalize
New `Exercise` fields are optional/defaulted. Legacy `MuscleCatalog` ids stored on
existing rows are canonicalized through `MuscleGroup.canonical(legacyID:)` on
read, and normalized once during `seedStarterLibraryIfNeeded`. The pre-migration
id list is written into the existing legacy `muscleGroups` tag field before
normalization, so no user data is destroyed and the change is reversible.

Legacy alias table (complete):

| legacy id | `MuscleGroup` |
|---|---|
| `abs` | `abdominals` |
| `obliques` | `abdominals` |
| `quads` | `quadriceps` |
| `delts`, `front-delts`, `rear-delts` | `shoulders` |
| `rhomboids` | `middleBack` |
| `lower-back` | `lowerBack` |
| `upper-chest` | `chest` |
| `hip-flexors` | `hipFlexors` |
| `chest`, `lats`, `traps`, `biceps`, `triceps`, `forearms`, `hamstrings`, `glutes`, `calves`, `adductors`, `abductors` | identity |

### D8 — exercise evidence is a second, generated citation table
The 60 DB++ references become `CitationRegistry.exerciseEvidence`, built from the
bundled JSON at first use and resolvable through the existing
`CitationRegistry.citation(forId:)` entry point (which gains a fall-through).
`CitationRegistry.all` — the curated coaching bibliography with its 1:1
`usageReasons` contract — is **not** touched, so `CitationIntegrityTests` keeps
passing unchanged. `docs/CITATIONS.md` gains a generated, delimited section, and
`scripts/check-citations-sync.sh` (wired into `make guardrails`) fails if it
drifts from the bundled data.

### D9 — DB++ `patterns` enrich, but do not replace, `MovementPattern`
Our 10-case `MovementPattern` drives weekly-plan focus selection and recovery
windows. DB++'s 86 in-use patterns map onto it (table in
`03-annotation-pipeline-and-schema.md` §5), giving an evidence-derived
classification in place of name heuristics. The 10-case enum itself does not
change.

### D10 — copy
- Home `This Week` keeps the row title **`Volume`**.
- `BodyPart`-era user-visible phrase "muscle group" is retained and now literally
  means one `MuscleGroup`.
- Suggested-workout chooser title stays **`View Suggested Workout`**; the choice
  buttons become the five style names; generated plan names become
  `Fitness Plan`, `Bodyweight Plan`, `Powerlifting Plan`, `Olympic Plan`,
  `Strongman Plan`.

### D11 — the 4 / 8 / 12 weekly set scale is unchanged
`WeeklySetProgress` (minimum 4, productive 8, maximum 12) and its zone colouring
carry over verbatim to muscle-group rows. `VolumeLandmarks` MEV/MAV/MRV bands are
re-expressed per `MuscleGroup` (table in `04-volume-accounting.md` §3).

### D12 — no CloudKit schema redeploy is required
All new fields are additive with defaults, which
`NSPersistentCloudKitContainer` handles by mirroring new optional columns. A
Production schema deploy is still needed before the next TestFlight build ships
the new fields — flag it in the phase 3 status note, do not attempt it from code.
