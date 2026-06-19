# Decisions — 2026-06-19 refinements

All decisions locked by user on 2026-06-19.

| # | Question | Answer | Rationale |
|---|----------|--------|-----------|
| R1 | Keep GZCLP/nSuns? | Eliminate | Internet-origin, no published study |
| R2 | Which programs to add? | DUP, GVT, Linear Periodization, Cluster Set | All have direct published studies |
| R3 | Must all routines have citations? | Yes | Core principle: science-based & transparent |
| R4 | Info button on group header or each row? | Group header | One summary per program family |
| R5 | Build-time fetch mechanism? | Shell script + Makefile | No Go dependency, conventional for Xcode projects |
| R6 | Bundled images strategy? | Fully network-loaded | Saves 19MB; cache on device; placeholder on failure |
| R7 | Show one or two exercise images? | Both side by side | Start + end position shows movement range |
| R8 | Exercise library link target? | GitHub exercise directory | Per-exercise, stable URL |
| R9 | Exercise detail fields? | Show ALL from free-exercise-db | HIG-compliant layout |
| R10 | Exercise favorites model? | `isFavorite: Bool` on Exercise | Additive, SwiftData, CloudKit-safe |
| R11 | Routine favorites model? | `favoriteRoutineIDs` in UserDefaults | WorkoutPlan is a value type, not SwiftData |
| R12 | Home favorites layout? | Combined section, Routines + Exercises | Hidden when empty |
| R13 | App logo source? | `images/ci_app_logo.jpeg` → PNG | 1024×1024, replace both iOS + watchOS icons |
| R14 | Coach button text? | "Start Coach's Workout", no subtitle | Single line, cleaner |
