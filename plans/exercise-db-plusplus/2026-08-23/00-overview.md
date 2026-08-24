# Exercise DB++ adoption — overview, research, and roadmap

**Date:** 2026-08-23
**Scope:** replace the `yuhonas/free-exercise-db` upstream with
`johnarleyburns/free-exercise-db-plusplus` (DB++), collapse the 8-part `BodyPart`
simplification and the 21-entry `MuscleCatalog` into DB++'s single 20-muscle
ontology, rebuild weekly volume accounting on DB++ direct/indirect/stabilizer set
credits, and replace the minimum/medium/maximal suggested-workout tiers with one
minimum target rendered in several **training styles**.

Everything below is grounded in the actual data (fetched and analysed 2026-08-23)
and the actual code paths in this repo. No further research is required to
implement any phase.

---

## 1. What DB++ actually is

`https://github.com/johnarleyburns/free-exercise-db-plusplus` — Unlicense
(public domain), same as upstream. Raw file:

```
https://raw.githubusercontent.com/johnarleyburns/free-exercise-db-plusplus/main/free-exercise-db-plusplus.json
```

1.8 MB, one JSON object:

```jsonc
{
  "metadata": {
    "schemaVersion": "0.3.0",          // 0.3.0 at time of writing
    "converterVersion": "0.8.0",
    "generatedAt": "2026-08-24T02:23:31Z",
    "upstream": { "project": "yuhonas/free-exercise-db", "sourceUrl": "...", "sha256": "d68a8174..." },
    "setCredits": { "direct": 1.0, "indirect": 0.5, "stabilizer": 0.0 },
    "setCreditEvidence": { "status": "supported_model", "interpretation": "...", "references": ["fractional_sets_meta_regression_2025"] },
    "evidence": {
      "references": { "<refId>": { "title", "type", "pmid"?, "doi"?, "url" } },   // 60 entries
      "patterns":   { "<patternId>": { "status", "summary", "references": [refId] } } // 89 entries
    },
    "muscleOntology": [ 20 muscle strings ],
    "sourceExerciseCount": 873, "outputExerciseCount": 873, "completeness": "full"
  },
  "exercises": {                        // keyed by exerciseId — a DICTIONARY, not an array
    "3_4_Sit-Up": {
      "exerciseId": "3_4_Sit-Up",
      "classification": { "trainingTypes": [...], "modalities": [...], "sportContexts": [...], "competitionMovements": [...] },
      "annotation": { "patterns": [...], "direct": [...], "indirect": [...], "stabilizers": [...],
                      "volumeEligible": true, "confidence": "high",
                      "reviewReasons": [...], "evidenceRefs": ["pattern:trunk_flexion"] },
      "source": { ...verbatim upstream record... }
    }
  }
}
```

### Verified facts (measured, not assumed)

| Check | Result |
|---|---|
| Exercise count | **873** — identical id set to our bundled `free-exercise-db.json` |
| `source` sub-object vs our current snapshot | **byte-identical for all 873 records, every field** |
| Bundled `Resources/ExerciseImages/<id>/` dirs | **873, all covered** — imagery needs zero work |
| Muscle ontology | 20 values (see §2) |
| `volumeEligible` | true for 673, false for 200 (123 stretching, 61 plyometrics, 14 cardio, 2 strength) |
| Exercises with empty `direct` | 200 — **exactly the 200 that are not volume-eligible** |
| `confidence` | high 785, medium 88, low 0 |
| `evidenceRefs` | 671 exercises carry ≥1 `pattern:<id>` ref; every referenced pattern exists in `evidence.patterns`; every pattern reference resolves to a real PMID/DOI |
| `trainingTypes` combos | `strength` 581, `stretching` 123, `plyometrics` 61, `powerlifting+strength` 38, `olympic_weightlifting+strength` 35, `strength+strongman` 21, `cardio` 14 |
| `modalities` | free_weight 302, other 211, bodyweight 111, cable 81, machine 67, kettlebell 53, band 20, medicine_ball 17, sled 12, foam_roll 11, rope 11, loaded_object 8 |
| `sportContexts` | general_fitness 873, powerlifting 38, weightlifting 35, strongman 21, gymnastics 6, crossfit 3 |
| `competitionMovements` | populated on 5 records only |
| `direct` muscles per volume-eligible exercise | 1 → 402, 2 → 217, 3 → 32, 4 → 19, 5 → 3 |
| `indirect` per volume-eligible exercise | 0 → 209, 1 → 292, 2 → 160, 3 → 12 |

Spot checks (these become test fixtures):

| Exercise | direct | indirect | stabilizers |
|---|---|---|---|
| `Barbell_Squat` | quadriceps, glutes | adductors | lower_back, hamstrings, calves |
| `Barbell_Deadlift` | glutes, hamstrings | quadriceps | lower_back, traps, forearms, lats |
| `Barbell_Bench_Press_-_Medium_Grip` | chest | triceps, shoulders | — |
| `Pullups` | lats | biceps, middle_back | forearms |
| `Standing_Military_Press` | shoulders | triceps | abdominals |
| `Barbell_Curl` | biceps | forearms | — |

**Set-credit model.** DB++ states one convention: `direct = 1.0`,
`indirect = 0.5`, `stabilizer = 0.0`, citing
`fractional_sets_meta_regression_2025` (PMID 41343037, *Sports Medicine*) — which
is **already in our registry as `pellandDoseResponse2026`**. Our current code
already uses 1.0/0.5 for primary/secondary (`TrainingFacts.secondaryWeight`), so
the model is unchanged; what changes is that the *role assignment* becomes
evidence-audited, and stabilizer-only involvement now correctly counts **zero**
(today a deadlift credits `lower-back`; DB++ says lower back is a stabilizer
there).

---

## 2. The ontology

DB++ `metadata.muscleOntology`, in file order:

```
abdominals, abductors, adductors, biceps, calves, chest, forearms, glutes,
hamstrings, lats, lower_back, middle_back, neck, quadriceps, shoulders, traps,
triceps, tibialis, rotator_cuff, hip_flexors
```

Direct-role exercise counts across the whole DB (volume-eligible only):

| muscle | direct | indirect | stabilizer |
|---|---|---|---|
| glutes | 179 | 16 | 2 |
| quadriceps | 129 | 28 | 2 |
| shoulders | 114 | 112 | 43 |
| chest | 94 | 8 | 0 |
| triceps | 88 | 90 | 16 |
| abdominals | 82 | 5 | 100 |
| lats | 69 | 1 | 19 |
| biceps | 65 | 75 | 0 |
| hamstrings | 56 | 56 | 57 |
| middle_back | 50 | 24 | 0 |
| traps | 40 | 47 | 39 |
| forearms | 16 | 61 | 168 |
| calves | 13 | 57 | 60 |
| adductors | 7 | 68 | 0 |
| rotator_cuff | 6 | 0 | 0 |
| neck | 5 | 0 | 0 |
| hip_flexors | 4 | 0 | 0 |
| lower_back | 4 | 0 | 145 |
| abductors | 2 | 0 | 0 |
| **tibialis** | **0** | 0 | 0 |

`tibialis` has **no** direct exercise anywhere in the database — a weekly target
for it could never be satisfied. This drives decision **D4**.

### Why our current two-level scheme is worse than DB++'s one level

Today we carry *both* `BodyPart` (8 coarse buckets: legs/back/chest/shoulders/
biceps/triceps/calves/abs) *and* `MuscleCatalog` (21 fine muscles). The fine
catalog's extra resolution is **fictional for 87% of the catalog**: `upper-chest`,
`front-delts`, `rear-delts`, `obliques`, `rhomboids` are only ever populated by
hand-written entries in `ExerciseLibrary.curated` — 5, 4, 4, 1 and 5 exercises
respectively out of 997 seeded rows. Every one of the 873 imported movements maps
`shoulders → delts`, never to front/rear delts. So Home's per-muscle list shows
"Front Delts 0 sets — Below 4-set minimum" in red essentially forever, and the
suggested-workout generator burns deficit dimensions it can never close.

DB++'s 20-value ontology sits exactly where the evidence is: it is fine enough to
answer "did I train my adductors?" and coarse enough that every dimension has real
exercises behind it. It replaces **both** of our layers with one.

---

## 3. Alternatives considered

| Option | Verdict |
|---|---|
| **A. Keep upstream free-exercise-db, hand-maintain our own annotation layer** | Rejected. That is precisely what DB++ already is, with 60 cited EMG/meta-analytic references and CI that revalidates against upstream. Re-deriving it in Swift literals gives us an unaudited copy to maintain forever. |
| **B. Adopt DB++ data but keep our 21-muscle `MuscleCatalog`, mapping DB++ → ours** | Rejected. Requires inventing a `shoulders → {front-delts, delts, rear-delts}` split the evidence does not support, and preserves the phantom-dimension bug above. Also contradicts the explicit request. |
| **C. Adopt DB++ and keep `BodyPart` as a display-only rollup over the new ontology** | Rejected for the volume surface (the request removes it), but note the *concept* survives as `MuscleGroup.region` (chest/back/shoulders/arms/core/legs/glutes) which we keep purely for grouping chips and section headers — never for volume math. |
| **D. Fetch DB++ at runtime / git submodule** | Rejected. NFR-3 forbids network at runtime and `scripts/check-no-network.sh` enforces it. The repo's established pattern is a committed snapshot plus `scripts/update-exercises.sh`; we keep it. |
| **E. Strip metadata from the bundled JSON to save space** | Rejected. The `evidence` block is what lets every muscle-role claim cite literature (HARD RULE). 1.8 MB against a ~40 MB image bundle is not worth the loss. |
| **F. Adopt DB++ `workout.schema.json` as our export interchange format** | Out of scope for this plan; noted as future work. Our export is a superset (sets, RPE, partners, assessments). |

**Chosen: A-through-F resolved as → adopt DB++ wholesale (option D's snapshot
mechanism, option C's region-as-grouping-only), collapse `BodyPart` +
`MuscleCatalog` into one `MuscleGroup` type whose raw values are DB++'s ontology
strings.**

---

## 4. Cross-cutting decisions

See `decisions.md` for the authoritative list (D1–D12). The ones that shape every
phase:

- **D2** — `MuscleGroup` (20 cases, raw values = DB++ strings) is the single
  canonical dimension. `BodyPart` and `Muscle`/`MuscleCatalog` are deleted.
- **D3** — set credits are direct 1.0 / indirect 0.5 / stabilizer 0.0, and an
  exercise with `volumeEligible == false` contributes **nothing** to weekly
  volume, regardless of its muscle lists.
- **D4** — 13 groups are *tracked* by default (targeted by the coach, always shown
  on Home); the other 7 are shown only when the user has actually trained them.
- **D6** — the suggested workout is one minimum target rendered in 5 **styles**.
- **D7** — schema changes are additive-only; legacy muscle ids are canonicalized
  on read and normalized once during seeding, with the pre-migration ids
  preserved in the existing legacy `muscleGroups` tag field so nothing is lost.

## 5. Standing rules for every phase

1. **Swift 6 strict concurrency, warning-free.** No suppressions.
2. **Logic in `CadenceCore`, headless presentation in `CadenceFeatures`, SwiftUI
   renders prepared state.** `CadenceFeatures` may not import SwiftUI/UIKit/etc.
3. **The XCUITest suite stays at exactly one iPhone test and one watch test.**
   New coverage extends the existing flow or goes to `swift test`.
4. **Every user-visible science claim resolves through `CitationRegistry` and
   renders with `CitationLink`.** Never show a raw citation id.
5. **Files under `Cadence/Cadence/Features/` stay ≤400 LOC** unless already
   grandfathered in `scripts/check-test-pyramid.sh`, and grandfathered ceilings
   may only shrink.
6. **Additive-only persistence.** Every new `@Model` property is optional or
   defaulted (CloudKit requirement).
7. `make ci` (build + `swift test` + guardrails) must be green before a phase is
   committed; `make smoke` additionally before any phase that touches Home or the
   suggested-workout UI.

## 6. Execution protocol for this plan

Per the request, and differing from the CLAUDE.md default:

1. Before starting a phase, **read `current_status.md`** and continue from its
   documented position.
2. Implement the phase.
3. Verify (`make ci`, plus `make smoke` where the phase says so).
4. **Update `current_status.md`** with what shipped, test counts, deviations, and
   the next phase.
5. **Commit** the phase — staging everything **except `current_status.md`**, which
   stays uncommitted by long-standing repo convention.
6. **Do not push.** Pushing is a separate, explicit instruction.

## 7. Phase roadmap

| # | Phase | File | Depends on | Touches UI? |
|---|---|---|---|---|
| 1 | Vendor the DB++ snapshot + decode it | `01-vendor-and-decode.md` | — | no |
| 2 | The `MuscleGroup` ontology | `02-muscle-group-ontology.md` | 1 | no |
| 3 | Annotation pipeline: templates, `Exercise` schema, seeding, export | `03-annotation-pipeline-and-schema.md` | 1, 2 | no |
| 4 | Volume accounting on the new ontology | `04-volume-accounting.md` | 2, 3 | no |
| 5 | Home "This Week": Volume becomes muscle-group volume | `05-home-this-week.md` | 4 | **yes** |
| 6 | Coach optimizer, picker, watch migrate; delete `BodyPart` | `06-coach-and-picker-migration.md` | 4 | **yes** |
| 7 | Suggested workouts: one target × training styles | `07-suggested-workout-styles.md` | 3, 4, 6 | **yes** |
| 8 | Evidence surfacing, citations, docs, attribution | `08-evidence-and-docs.md` | 3, 7 | **yes** |

Phases are strictly sequential — each assumes the previous is on `main`.
