# 01 — Routine Science Audit (Phase A)

## Problem
Current routine catalog includes GZCLP (internet blog) and nSuns (Reddit) which have no
published scientific study. All built-in routines must cite peer-reviewed literature.

## Programs to ELIMINATE
- **GZCLP** (4 routines: `preset-gzclp-*`) — Cody Lefever blog, no study
- **nSuns** (4 routines: `preset-nsuns-*`) — Reddit-origin, no study

## Programs to KEEP (with new citations)
| Group | Citation |
|-------|----------|
| 5×5 | Krieger 2010, JSCR 24(4) — multi-set meta-analysis |
| 5/3/1 | Rhea & Alderman 2004, RQES 75(4) — periodization meta-analysis |
| PPL | Schoenfeld 2019 (existing `frequencyMeta`) |
| Split Templates | Same frequency literature |
| Calisthenics | Calatayud 2015, JSSM 14(3) — bodyweight activation |
| Olympic | Channell & Barfield 2008, JSCR 22(5) — Oly vs traditional |

## Programs to ADD
| Group | Routines | Citation |
|-------|----------|----------|
| DUP | 3 days: Heavy/Hypertrophy/Power | Zourdos 2016, JSCR 30(3) |
| German Volume Training | 1 routine: 10×10 compound + accessories | Amirthalingam 2017, JSCR 31(11) |
| Linear Periodization | 4 weeks: 4×12→4×10→4×8→5×5 | Williams 2017, Sports Med 47(3) |
| Cluster Set Training | Rest-pause clusters on compounds | Tufano 2017, JSCR 31(11) |

## Data model
New `RoutineInfo` struct in CadenceCore: summary text + `[Citation]`.
Static catalog keyed by group name.

## UI
Info button (ℹ) right-justified on each Section header in PlanningView.
Tapping presents `RoutineInfoSheet` with summary + citation card + paper link.

## Files
- `CadenceCore/.../Citation.swift` — 8 new citations
- `CadenceCore/.../WorkoutPlan.swift` — drop GZCLP/nSuns, add new presets, add RoutineInfo
- `Cadence/.../PlanningView.swift` — update RoutineGroup, info button
- New: `Cadence/.../RoutineInfoSheet.swift`
