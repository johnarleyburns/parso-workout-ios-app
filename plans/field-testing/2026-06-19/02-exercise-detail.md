# 02 — Exercise Data Pipeline + Detail Redesign (Phases B + C)

## Build-time data fetch (Phase B)
- `scripts/update-exercises.sh`: curl latest JSON from GitHub raw, overwrite backup
- `make update-exercises` target
- Committed `free-exercise-db.json` is always the fallback
- Remove `exercise-images/` directory (19MB) from bundle
- Update `Package.swift` to drop `.copy("Resources/exercise-images")`

## Runtime image loading (Phase B)
- Base URL: `https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/`
- Image paths: `{id}/images/0.jpg` and `{id}/images/1.jpg`
- `ExerciseLibrary.imageURL()` returns remote URL instead of bundle URL
- `URLCache`-based caching (~50MB disk)
- Graceful failure: SF Symbol `photo.slash` + "Image not available"

## Exercise detail redesign (Phase C)
Show ALL free-exercise-db fields in HIG-compliant layout:
- Two images side by side (start + end position)
- Facet tags: level, equipment, mechanics, force, category
- Primary + secondary muscles
- Step-by-step instructions
- Link: "View in exercise library" → GitHub exercise directory
- Attribution footer: "Exercise data: free-exercise-db (public domain)"

## About page
Add "Exercise Library" section crediting free-exercise-db with GitHub link.

## Files
- New: `scripts/update-exercises.sh`, Makefile target
- `CadenceCore/Package.swift` — remove image copy
- Delete: `CadenceCore/.../Resources/exercise-images/`
- `CadenceCore/.../ImportedExerciseLibrary.swift` — remote URLs
- `Cadence/.../ExerciseDetailView.swift` — full redesign
- `Cadence/.../AboutView.swift` — attribution section
