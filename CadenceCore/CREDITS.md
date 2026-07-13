# Credits — vendored data

## free-exercise-db
- Source: https://github.com/yuhonas/free-exercise-db
- Pinned commit: `b0eed061e1c832b3ed815fbaa4b45b3cdc14df49`
- License: **Unlicense** (public domain) — see
  `Sources/CadenceCore/Resources/free-exercise-db.LICENSE`. No attribution or
  share-alike is required; this credit is open-source hygiene, not an obligation.
- What we use: exercise names, instructions, muscles, equipment, level, and the
  public-domain demonstration images. The data is transformed on-device into our
  own taxonomy (`MuscleCatalog`, `ExerciseCategory`, `Equipment`, …) by
  `ImportedExerciseLibrary`; our curated facets win on conflict (strength-pivot P2,
  decision D2).
- Images are **bundled**, not fetched at runtime (NFR-3): `scripts/build-exercise-images.sh`
  downloads them once from the same pinned commit, downscales to HEIC (≤400px,
  quality 70) with `sips`, and writes them to
  `Sources/CadenceCore/Resources/ExerciseImages/<id>/{0,1}.heic` (~30 MB, committed).
  `ExerciseImageCatalog` resolves them from `Bundle.module`; `scripts/check-no-network.sh`
  keeps the runtime network-free.
