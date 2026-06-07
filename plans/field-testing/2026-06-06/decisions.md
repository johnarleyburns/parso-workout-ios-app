# Decisions — 2026-06-06 field-testing plan

Approved by the field tester ("proceed with all defaults"). These are binding for
sections 02–07 and resolve the open questions in `00-overview.md` §5.

## Cross-cutting
1. **Steps/activity** → keep a compact "Activity" block inside **Stats**, removed from Home.
2. **PR rule default** → **estimated 1RM**, user-configurable (top-weight / best-volume).
3. **1RM formula** → **Epley** (`w·(1+reps/30)`).
4. **Units** → **global default unit** in Settings; the set-entry control **always shows both lb & kg and auto-fills** the other.
5. **Rollout** → **incremental PR per section** (02→07), each green before the next.

## §02 Session engine
6. **Auto-terminate** → "Still training?" prompt with countdown; **auto-SAVE & finalize** on no response (never silent discard).
7. **Idle timeout** → **10 min default, adjustable**; paused while a timer/round is actively running.
8. **Concurrency** → **one active session**; Start offers Resume vs Start New if one is live.
9. **Type picker (v1)** → Weight Training, Run, Walk, Cycle, HIIT, Boxing, Other.

## §03 Exercise database
10. **Seed size** → **~300 original entries**, exrx-structured (exrx data is licensed — structure only, no copy).
11. **Equipment** → `barbell, dumbbell, cable, machine (isolateral / bilateral), bodyweight, plyometric, kettlebell, band, smith`.
12. **Muscle taxonomy** → muscle group + specific muscle + **synonym map** (scientific ↔ colloquial).

## §04 Weight training
13. **Partner HealthKit** → partner sets **never** written to owner's HealthKit; local only.
14. **Partner export** → **included** in JSON/CSV, tagged by person.
15. **Dual-unit rounding** → show **exact** converted value; optional plate-round toggle **off** by default.
16. **Templates** → remove from UI, keep schema; **"Reuse workout"** clones a past session.

## §05 Cardio GPS
17. **GPS scope** → Run / Walk / Cycle get GPS+map; indoor = timer-only (no separate screen v1).
18. **Map** → **MapKit** (no new deps).
19. **Auto-pause** → off by default, toggle in Settings.

## §06 Interval engine
20. **Color system** → green=work, yellow=last 30s, flashing=last 3s, red=rest; applied to **boxing AND HIIT**; colors adjustable for color-blindness.
21. **HIIT presets** → Tabata, Norwegian 4×4, + custom builder.
22. **Boxing presets** → 3min/1min, 2min/30s, + custom (length / rest / count).
23. **Cues** → audio beeps + haptics every transition; optional spoken announcements.
24. **HealthKit** → save summary `HKWorkout` (HIIT / boxing).

## §07 Rollout
25. **Migration** → additive schema only, no destructive migration, new fields optional/defaulted (CloudKit rules).
