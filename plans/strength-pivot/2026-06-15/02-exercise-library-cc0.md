# 02 — Public-domain (CC0) science-grade exercise library

## Problem / why
Today's catalog is ~190 hand-written entries, and the batch-8 work links *out* to
EXRX.NET because EXRX content is copyrighted (we can't embed it). For a science-based
coach we want a **large, embeddable, freely-licensed** library — instructions,
muscles, equipment, and images that live **on-device** (consistent with privacy +
offline + open-source), with **no attribution/share-alike strings**.

## Research findings (2026-06-15)
- **free-exercise-db** (`yuhonas/free-exercise-db`): **~800+ exercises, Unlicense
  (public domain)**, JSON-per-exercise. Schema: `id, name, force, level, mechanic,
  equipment, primaryMuscles, secondaryMuscles, instructions, category, images`. Images
  are **public-domain**, hosted on GitHub raw (`…/exercises/<path>`). Some fields
  incomplete; ~25 duplicate images. **→ Recommended base: Unlicense means we can embed
  data + images with zero obligations.**
- **wger** (`wger-project`): 845+ exercises, app AGPL, **data CC-BY-SA 3.0**
  (attribution + share-alike). Richer/multilingual but copyleft — attribution required
  and SA could encumber our derived dataset. **→ Optional secondary source only if we
  accept attribution; not the base.**
- Muscle/anatomy imagery can additionally come from **Wikimedia Commons** (CC) if we
  want body diagrams, but free-exercise-db images already cover movement demos.

## Decision (D2)
Base = **free-exercise-db (Unlicense)**, vendored at a pinned commit. Layer our own
science facets on top (our `MuscleCatalog` ids, `BodyPart` mapping, `Mechanics`,
`Force`, `Equipment`, plus engine facets like `isCompound`, SFR class, default rep
range). Do **not** depend on wger unless the user opts into attribution.

## Integration plan (P2)
1. **Vendor + transform offline** (a build/script step, not runtime): pull the JSON at
   a pinned commit, run a Swift/script transformer that:
   - de-dupes; normalizes names; maps their muscle strings → our `MuscleCatalog` ids
     (a hand-checked mapping table — the curation step, since their muscle taxonomy is
     coarser); derives `BodyPart` via existing `BodyPart.parts(forMuscleIDs:)`.
   - fills our `category` (push/pull/legs/core/plyometrics/other) from their
     `force`/`mechanic`/muscles.
   - emits a generated `ExerciseLibrary+Imported.swift` (or a bundled JSON the app
     seeds from) so the catalog is data, not 800 hand-written literals.
2. **Bundle images on-device**: copy the PD images into an asset catalog / bundled
   folder; reference by exercise id. No network needed → offline + private. (Cap size;
   downscale; ~800 images is manageable; lazy-load.)
3. **Keep our curated facets authoritative** where they conflict (we trust our
   `MuscleCatalog` mapping over their coarse strings).
4. **Retire EXRX links** from the picker (replace the external "info" button with an
   in-app exercise detail: PD instructions + image + muscles). Optionally keep a
   generic "search the web" affordance, but no EXRX dependence.
5. **Seeding**: bump `seedVersion`; additive upsert by name (existing
   `seedStarterLibraryIfNeeded` pattern) so user/custom exercises are untouched and
   existing installs gain the new entries + facets.
6. **Attribution file**: include the Unlicense text + a `CREDITS.md` noting the source
   commit (good open-source hygiene even though PD requires none).

## Data-model deltas (additive)
- `ExerciseTemplate`/`Exercise`: add optional `instructions: [String]` (PD steps),
  `imageName: String?` (bundled asset), `level: String?` (beginner/…); keep existing
  facets. All optional/defaulted → CloudKit-safe.
- A bundled `exercise-library.json` (PD) + image assets.

## Testing
- Transformer is a `swift test`-covered pure function: every imported entry maps to ≥1
  known `MuscleCatalog` id (extends the existing `testCatalogIntegrity`); no dup names;
  every `imageName` resolves to a bundled asset; count ≈ expected.
- UI: exercise detail shows instructions + image offline (airplane mode).

## Open
- D2 source confirmation (free-exercise-db base; wger yes/no).
- App binary size budget for ~800 bundled images (downscale / WebP / on-demand asset
  pack?). Decide acceptable size; fallback = ship without images first, add via P2.1.
