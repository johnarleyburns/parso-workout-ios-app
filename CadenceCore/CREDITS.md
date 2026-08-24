# Credits — vendored data

## free-exercise-db++
- Source: https://github.com/johnarleyburns/free-exercise-db-plusplus
- Vendored snapshot: schema `0.3.0`, converter `0.8.0`, generated
  `2026-08-24T02:23:31Z`, 873 exercises.
- License: **Unlicense** (public domain) — see
  `Sources/CadenceCore/Resources/free-exercise-db-plusplus.LICENSE`. No
  attribution or share-alike is required; this credit is open-source hygiene, not
  an obligation.
- What it is: an evidence-audited annotation layer over `yuhonas/free-exercise-db`.
  Every upstream record is preserved **verbatim** under each entry's `source`
  field — we verified the two are byte-identical for all 873 records and every
  field before adopting it — and DB++ adds:
  - a normalized 20-muscle ontology (`metadata.muscleOntology`), which
    `MuscleGroup` mirrors exactly;
  - `direct` / `indirect` / `stabilizers` muscle roles per movement, with the
    published set-credit convention 1.0 / 0.5 / 0.0;
  - `volumeEligible`, which excludes stretching, plyometrics and cardio from
    weekly volume;
  - movement classification (`trainingTypes`, `modalities`, `sportContexts`,
    `competitionMovements`) and canonical movement `patterns`;
  - 60 literature references with PMIDs/DOIs and 89 pattern-level evidence
    summaries, which is how every muscle attribution the app shows can cite the
    work it came from.
- It is decoded by `ExerciseDatabase` and transformed into our taxonomy by
  `ImportedExerciseLibrary`.
- Refresh it with `make update-exercises`, which validates the snapshot against
  `scripts/validate-exercise-db.py` and refuses to install one that fails.

## free-exercise-db
- Source: https://github.com/yuhonas/free-exercise-db
- Pinned commit: `b0eed061e1c832b3ed815fbaa4b45b3cdc14df49`
- License: **Unlicense** (public domain).
- Reached through DB++'s `source` field: exercise names, instructions, muscles,
  equipment, level, and the public-domain demonstration images.
- Images are **bundled**, not fetched at runtime (NFR-3):
  `scripts/build-exercise-images.sh` downloads them once from the pinned commit,
  downscales to HEIC (≤400px, quality 70) with `sips`, and writes them to
  `Sources/CadenceCore/Resources/ExerciseImages/<id>/{0,1}.heic` (~30 MB,
  committed). `ExerciseImageCatalog` resolves them from `Bundle.module`;
  `scripts/check-no-network.sh` keeps the runtime network-free.
