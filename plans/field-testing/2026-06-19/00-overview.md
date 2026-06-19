# Post-Field-Testing Refinements — Overview

**Date:** 2026-06-19
**Stream:** `plans/field-testing/2026-06-19/`
**Continuity:** builds on `plans/field-testing/2026-06-18/`

---

## Scope

Six deliverables from field-testing feedback:

| Phase | Deliverable |
|-------|-------------|
| **0** | App logo replacement + "Start Coach's Workout" copy fix |
| **A** | Routine science audit: drop unscientific programs, add studied ones, citations + info buttons |
| **B** | Exercise data pipeline: build-time JSON fetch, remove bundled images, runtime image loading |
| **C** | Exercise detail redesign: all free-exercise-db fields, two images, library link, attribution |
| **D** | Favorites: routine + exercise favorites, Home page favorites section |

## Locked Decisions

| # | Decision | Resolution |
|---|----------|------------|
| R1 | GZCLP and nSuns | **Eliminate** — internet-origin, no published study |
| R2 | New programs to add | DUP, German Volume Training, Linear Periodization, Cluster Set Training |
| R3 | All routines must have citations | Yes |
| R4 | Info button placement | On group header |
| R5 | Build-time JSON fetch | Shell script + Makefile target |
| R6 | Exercise images | Fully network-loaded at runtime, remove bundled 19MB |
| R7 | Image count | Show both (start + end) side by side |
| R8 | Exercise page link | GitHub exercise directory |
| R9 | Exercise detail | Show ALL free-exercise-db fields |
| R10 | Exercise favorites | `isFavorite: Bool` on Exercise model |
| R11 | Routine favorites | `favoriteRoutineIDs` in AppSettings (UserDefaults) |
| R12 | Home favorites | Combined section, Routines + Exercises |
| R13 | App logo | Replace with `images/ci_app_logo.jpeg` (convert to PNG) |
| R14 | Coach button text | "Start Coach's Workout" (single line, no subtitle) |

## Dependencies

- Phase 0: independent
- Phase A: independent
- Phase B: independent
- Phase C: depends on B
- Phase D: depends on A
